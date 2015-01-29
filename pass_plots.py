#!/usr/bin/env python
import glob
from optparse import OptionParser
import os
import time
import cPickle
import re
import numpy as np
import numpy.ma as ma
import logging
from logging.handlers import SMTPHandler
from itertools import izip, cycle
import mx.DateTime
import jinja2
import json
import matplotlib
# Matplotlib setup
# Use Agg backend for command-line (non-interactive) operation
if __name__ == '__main__':
    matplotlib.use('Agg')
import matplotlib.pyplot as plt
plt.rcParams['lines.markeredgewidth'] = 0

from Chandra.Time import DateTime
from Ska.DBI import DBI
import Ska.Table
import Ska.Shell
import Ska.report_ranges
from Ska.engarchive import fetch
from mica.archive import aca_hdr3
from Ska.Matplotlib import plot_cxctime
from Chandra.cmd_states import get_cmd_states
import chandra_models
import xija

import characteristics

log = logging.getLogger()
log.setLevel(logging.DEBUG)

# emails...
smtp_handler = SMTPHandler('localhost',
                           'aca@head.cfa.harvard.edu',
                           'aca@head.cfa.harvard.edu',
                           'perigee health mon')

smtp_handler.setLevel(logging.WARN)
has_smtp = None
for h in log.handlers:
    if isinstance(h, logging.handlers.SMTPHandler):
        has_smtp = True
if not has_smtp:
    log.addHandler(smtp_handler)

colors = characteristics.plot_colors
pass_color_maker = cycle(colors)
obsid_color_maker = cycle(colors)

task = 'perigee_health_plots'
SKA = os.environ['SKA']
TASK_SHARE = os.path.join(os.environ['SKA'], 'share', 'perigee_health_plots')


#TASK_DIR = '/proj/sot/ska/www/ASPECT/perigee_health_plots'
#URL = 'http://cxc.harvard.edu/mta/ASPECT/perigee_health_plots'
#PASS_DATA = os.path.join(TASK_DIR, 'PASS_DATA')
#SUMMARY_DATA = os.path.join(TASK_DIR, 'SUMMARY_DATA')

## Django setup for template rendering
#import django.template
#import django.conf
#if not django.conf.settings._target:
#    try:
#        django.conf.settings.configure()
#    except RuntimeError, msg:
#        print msg

jinja_env = jinja2.Environment(
    loader=jinja2.FileSystemLoader(os.path.join(TASK_SHARE, 'templates')))


def get_options():
    parser = OptionParser(usage='pass_plots.py [options]')
    parser.set_defaults()
    parser.add_option("-v", "--verbose",
                      type='int',
                      default=1,
                      help="Verbosity (0=quiet, 1=normal, 2=debug)",
                      )
    parser.add_option("--web_dir",
                      default="%s/www/ASPECT/%s" % (SKA, task),
                      help="Output web directory")
    parser.add_option("--data_dir",
                      default="%s/data/%s" % (SKA, task),
                      help="Output data directory")
    parser.add_option("--web_server",
                      default="http://cxc.harvard.edu")
    parser.add_option("--url_dir",
                      default="/mta/ASPECT/%s" % task)
    parser.add_option("--days_back",
                      type='int',
                      default=30,
                      help="Number of days back to process")
    parser.add_option("--start_time",
                      default=None)
    (opt, args) = parser.parse_args()
    return opt, args


def aca_ccd_model(tstart, tstop, init_temp):
    cmd_states = get_cmd_states.fetch_states(tstart,
                                             tstop,
                                             vals=['obsid',
                                                   'pitch',
                                                   'q1', 'q2', 'q3', 'q4'])
    model_spec = chandra_models.get_xija_model_file('aca')
    model = xija.ThermalModel('aca', start=tstart, stop=tstop, model_spec=model_spec)
    times = np.array([cmd_states['tstart'], cmd_states['tstop']])
    model.comp['pitch'].set_data(cmd_states['pitch'], times)
    model.comp['aca0'].set_data(init_temp, tstart)
    model.comp['aacccdpt'].set_data(init_temp, tstart)
    model.make()
    model.calc()
    return model


def retrieve_perigee_telem(start='2009:100:00:00:00.000',
                           stop=None,
                           pass_data_dir='.',
                           redo=False):
    """
    Retrieve perigee pass and other 8x8 image telemetry.

    Telemetry is stored in directories named by datestart in the PASS_DATA
    directory.
    The file pass_times.txt in each directory contains the time range that
    has been queried for 8x8 image data

    :param start: Chandra.Time compatible time for beginning of range
    :param stop: Chandra.time compatible time for end of range
    :rtype: list of updated directories
    """

    tstart = DateTime(start)
    # default tstop should be now
    if stop is None:
        tstop = DateTime(time.time(), format='unix')

    log.info("retrieve_perigee_telem(): Checking for current telemetry from %s"

             % tstart.date)

    pass_time_file = 'pass_times.txt'
    aca_db = DBI(dbi='sybase', server='sybase',
                 user='aca_read', database='aca')
    obsids = aca_db.fetchall("""SELECT obsid,obsid_datestart,obsid_datestop
                                from observations
                                where obsid_datestart > '%s'
                                and obsid_datestart < '%s' order by obsid_datestart"""
                             % (tstart.date, tstop.date))

    # Get contiguous ER chunks, which are largely perigee passes
    chunks = []
    chunk = {'start': None,
             'stop': None}
    for obsid in obsids:
        # If a OR, end a "chunk" of ER unless undefined
        # (this should only append on the first OR after one or more ERs)
        if obsid['obsid'] < 40000:
            if chunk['start'] is not None and chunk['stop'] is not None:
                chunks.append(chunk.copy())
                chunk = {'start': None,
                         'stop': None}
        else:
            if chunk['start'] is None:
                chunk['start'] = obsid['obsid_datestart']
            chunk['stop'] = obsid['obsid_datestop']

    pass_dirs = []
    # for each ER chunk get telemetry
    for chunk in chunks:
        er_start = chunk['start']
        er_stop = chunk['stop']
        log.debug("checking for %s pass" % er_start)
        if (DateTime(er_stop).secs - DateTime(er_start).secs > 86400 * 2):
            log.warn("Skipping %s pass, more than 48 hours long" % er_start)
            continue
        er_year = DateTime(er_start).mxDateTime.year
        year_dir = os.path.join(pass_data_dir, "%s" % er_year)
        if not os.access(year_dir, os.R_OK):
            os.mkdir(year_dir)
        pass_dir = os.path.join(pass_data_dir, "%s" % er_year, er_start)
        pass_dirs.append(pass_dir)
        if not os.access(pass_dir, os.R_OK):
            os.mkdir(pass_dir)
        made_timefile = os.path.exists(os.path.join(pass_dir, pass_time_file))
        if made_timefile:
            pass_done = Ska.Table.read_ascii_table(
                os.path.join(pass_dir, pass_time_file))
            if ((pass_done['obsid_datestart'] == er_start)
                    & (pass_done['obsid_datestop'] == er_stop)):
                log.debug("%s times match" % pass_dir)
                continue
            else:
                log.info("pass %s exists but needs updating" % er_start)
                redo = True
        if not made_timefile or redo:
            f = open(os.path.join(pass_dir, pass_time_file), 'w')
            f.write("obsid_datestart,obsid_datestop\n")
            f.write("%s,%s\n" % (er_start, er_stop))
            f.close()
    return pass_dirs


class MissingDataError(Exception):
    """
    Special error for the case when there is missing telemetry
    """
    pass


def perigee_parse(pass_dir, min_samples=5, time_interval=20):
    """
    Determine TEC DAC level and temperatures from available telemetry.
    Create telemetry structure.

    For the supplied telem directory (pass_dir) read and concatenate the
    CCDM telemetry and the ACA0 telemetry (by slot).

    For each "time_interval" determine if the minimum number of telemetry
    samples "min_samples" are supplied. Skip intervals which do not have
    the minimum number of samples in all slots.

    :param pass_dir: directory containing CCDM and ACA0 telemetry
    :param min_samples: int, min num of samples to be contained in time_interval
    :param time_interval: int seconds, telemetry "chunking" interval
    :returns: reduced telemetry
    :rtype: dict
    """

    log.info("perigee_parse(): parsing %s" % pass_dir)

    pass_time_file = 'pass_times.txt'
    if not os.path.exists(os.path.join(pass_dir, pass_time_file)):
        raise MissingDataError("Missing telem for pass %s" % pass_dir)
    pass_times = Ska.Table.read_ascii_table(os.path.join(pass_dir,
                                                         pass_time_file))
    mintime = pass_times[0].obsid_datestart
    maxtime = pass_times[0].obsid_datestop

    hdr3 = aca_hdr3.MSIDset(['dac', 'ccd_temp', 'aca_temp'],
                            mintime, maxtime)

    parsed_telem = {'obsid': fetch.MSID('COBSRQID', mintime, maxtime),
                    'dac': hdr3['dac'],
                    'aca_temp': hdr3['aca_temp'],
                    'ccd_temp': hdr3['ccd_temp']}

    return parsed_telem


def get_telem_range(telem):
    # find the 5th and 95th percentiles
    sorted = np.sort(telem)
    ninety_five = sorted[int(len(sorted) * .95)]
    five = sorted[int(len(sorted) * .05)]
    mean = telem.mean()
    # 10% = (ninety_five - five)/9.
    # min = five - 10%
    # max = ninety_five + 10%
    return [five - ((ninety_five - five) / 9.),
            ninety_five + ((ninety_five - five) / 9.)]


def plot_pass(telem, pass_dir, url, redo=False):
    """
    Make plots of of TEC DAC level and ACA and CCD temperatures from
    8x8 image telemetry.
    Create html for the per-pass page to contain the figures.

    :param telem: telem dict as created by perigee_parse()
    :param pass_dir: telemetry pass directory
    :param redo: remake image files if already present?

    """

    filelist = ('dacvsdtemp.png', 'dac.png', 'aca_temp.png', 'ccd_temp.png',
                'obslist.htm', 'index.html')
    missing = 0
    for file in filelist:
        if not os.path.exists(os.path.join(pass_dir, file)):
            missing = 1
    if missing == 0 and not redo:
        return 0
    log.info('making plots in %s' % pass_dir)
    tfig = {}
    tfig['dacvsdtemp'] = plt.figure(num=1, figsize=(4, 3))
    tfig['dac'] = plt.figure(num=2, figsize=(4, 3))
    tfig['aca_temp'] = plt.figure(num=3, figsize=(4, 3))
    tfig['ccd_temp'] = plt.figure(num=4, figsize=(4, 3))

    obslist = open(os.path.join(pass_dir, 'obslist.htm'), 'w')
    obslist.write(
        "<TABLE BORDER=1><TR><TH>obsid</TH><TH></TH>"
        "<TH>start</TH><TH>stop</TH></TR>\n")
    uniq_obs = np.unique(telem['obsid'].vals)

    # in reverse order for the ER table to look right
    for obsid in uniq_obs[::-1]:
        obsmatch = np.flatnonzero(telem['obsid'].vals == obsid)
        curr_color = obsid_color_maker.next()
        tstart = telem['obsid'].times[obsmatch][0]
        tstop = telem['obsid'].times[obsmatch][-1]
        time_idx = (telem['dac'].times >= tstart) & (telem['dac'].times <= tstop)
        if not np.any(time_idx):
            continue
        obslist.write(
            "<TR><TD>%d</TD><TD BGCOLOR=\"%s\">&nbsp;</TD>"
            "<TD>%s</TD><TD>%s</TD></TR>\n"
            % (obsid,
               curr_color,
               DateTime(tstart).date,
               DateTime(tstop).date,
               ))


        plt.figure(tfig['dacvsdtemp'].number)
        rand_obs_dac = (telem['dac'].vals[time_idx]
                        + np.random.random(len(telem['dac'].vals[time_idx])) - .5)
        plt.plot(telem['aca_temp'].vals[time_idx] - telem['ccd_temp'].vals[time_idx],
                 rand_obs_dac,
                 color=curr_color,
                 marker='.', markersize=1)
        plt.figure(tfig['dac'].number)
        plot_cxctime(telem['dac'].times[time_idx],
                     rand_obs_dac,
                     color=curr_color, marker='.')
        plt.figure(tfig['aca_temp'].number)
        plot_cxctime(telem['aca_temp'].times[time_idx],
                     telem['aca_temp'].vals[time_idx],
                     color=curr_color, marker='.')
        plt.figure(tfig['ccd_temp'].number)
        plot_cxctime(telem['ccd_temp'].times[time_idx],
                     telem['ccd_temp'].vals[time_idx],
                     color=curr_color, marker='.')

    obslist.write("</TABLE>\n")
    obslist.close()

    aca_temp_lims = get_telem_range(telem['aca_temp'].vals)
    ccd_temp_lims = get_telem_range(telem['ccd_temp'].vals)

    h = plt.figure(tfig['dacvsdtemp'].number)
    plt.ylim(characteristics.dacvsdtemp_plot['ylim'])
    plt.ylabel('TEC DAC Control Level')
    plt.xlim(characteristics.dacvsdtemp_plot['xlim'])
    plt.xlabel("ACA temp - CCD temp (C)\n\n")
    h.subplots_adjust(bottom=0.2, left=.2)
    plt.savefig(os.path.join(pass_dir, 'dacvsdtemp.png'))
    plt.close(h)

    h = plt.figure(tfig['dac'].number)
    plt.ylim(characteristics.dac_plot['ylim'])
    plt.ylabel('TEC DAC Control Level')
    h.subplots_adjust(left=.2)
    plt.savefig(os.path.join(pass_dir, 'dac.png'))
    plt.close(h)

    h = plt.figure(tfig['aca_temp'].number)
    plt.ylabel('ACA temp (C)')
    plt.ylim(min(characteristics.aca_temp_plot['ylim'][0],
                 aca_temp_lims[0]),
             max(characteristics.aca_temp_plot['ylim'][1],
                 aca_temp_lims[1]))
    h.subplots_adjust(left=0.2)
    plt.savefig(os.path.join(pass_dir, 'aca_temp.png'))
    plt.close(h)

    h = plt.figure(tfig['ccd_temp'].number)
    h.subplots_adjust(left=0.2)
    plt.ylim(min(characteristics.ccd_temp_plot['ylim'][0],
                 ccd_temp_lims[0]),
             max(characteristics.ccd_temp_plot['ylim'][1],
                 ccd_temp_lims[1]))
    plt.ylabel('CCD temp (C)')

    plt.savefig(os.path.join(pass_dir, 'ccd_temp.png'))
    plt.close(h)

    pass_index_template = jinja_env.get_template('pass_index_template.html')
    pass_index_page = pass_index_template.render(task={'url': url})
    pass_fh = open(os.path.join(pass_dir, 'index.html'), 'w')
    pass_fh.write(pass_index_page)
    pass_fh.close()


def per_pass_tasks(pass_tail_dir, opt):

    tfile = 'telem.pickle'
    pass_data_dir = os.path.join(opt.data_dir, 'PASS_DATA', pass_tail_dir)
    if not os.path.exists(pass_data_dir):
        os.makedirs(pass_data_dir)
    reduced_data = perigee_parse(pass_data_dir)


    telem_time_file = 'telem_time.htm'
    pass_web_dir = os.path.join(opt.web_dir, 'PASS_DATA', pass_tail_dir)
    if not os.path.exists(pass_web_dir):
        os.makedirs(pass_web_dir)
    if not os.path.exists(os.path.join(pass_web_dir, telem_time_file)):
        tf = open(os.path.join(pass_web_dir, telem_time_file), 'w')
        tf.write("<TABLE BORDER=1>\n")
        tf.write("<TR><TH>datestart</TH><TH>datestop</TH></TR>\n")
        tf.write("<TR><TD>%s</TD><TD>%s</TD></TR>\n" %
                 (DateTime(reduced_data['ccd_temp'].times[0]).date,
                  DateTime(reduced_data['ccd_temp'].times[-1]).date))
        tf.write("</TABLE>\n")
        tf.close()

    # cut out nonsense bad data
    types = ['aca_temp', 'ccd_temp', 'dac']
    filters = characteristics.telem_chomp_limits
    for type in filters.keys():
        if 'max' in filters[type]:
            goods = np.flatnonzero(reduced_data[type].vals <= filters[type]['max'])
            maxbads = np.flatnonzero(reduced_data[type].vals > filters[type]['max'])
            for bad in maxbads:
                log.info("filtering %s,%s,%6.2f" %
                         (DateTime(reduced_data[type].times[bad]).date,
                          type,
                          reduced_data[type].vals[bad]))

            for ttype in types:
                reduced_data[ttype].vals.mask[maxbads] = ma.masked
        if 'min' in filters[type]:
            goods = np.flatnonzero(reduced_data[type].vals >= filters[type]['min'])
            minbads = np.flatnonzero(reduced_data[type].vals < filters[type]['min'])
            for bad in minbads:
                log.info("filtering %s,%s,%6.2f" %
                         (DateTime(reduced_data[type].times[bad]).date,
                          type,
                          reduced_data[type].vals[bad]))
            for ttype in types:
                reduced_data[ttype].vals.mask[maxbads] = ma.masked

    # limit checks
    limits = characteristics.telem_limits
    pass_url = opt.web_server + os.path.join(
        opt.url_dir, 'PASS_DATA', pass_tail_dir)
    for type in limits.keys():
        if 'max' in limits[type]:
            if ((max(reduced_data[type].vals) > limits[type]['max'])
                and not os.path.exists(
                    os.path.join(pass_data_dir, 'warned.txt'))):
                warn_text = (
                    "Warning: Limit Exceeded, %s of %6.2f is > %6.2f \n at %s"
                    % (type,
                       max(reduced_data[type].vals),
                       limits[type]['max'],
                       pass_url))
                log.warn(warn_text)
                warn_file = open(
                    os.path.join(pass_data_dir, 'warned.txt'), 'w')
                warn_file.write(warn_text)
                warn_file.close()

        if 'min' in limits[type]:
            if ((min(reduced_data[type].vals) < limits[type]['min'])
                and not os.path.exists(
                    os.path.join(pass_data_dir, 'warned.txt'))):
                warn_text = (
                    "Warning: Limit Exceeded, %s of %6.2f is < %6.2f \n at %s"
                    % (type,
                       min(reduced_data[type].vals),
                       limits[type]['min'],
                       pass_url))
                log.warn(warn_text)
                warn_file = open(
                    os.path.join(pass_data_dir, 'warned.txt'), 'w')
                warn_file.write(warn_text)
                warn_file.close()

    plot_pass(reduced_data, pass_web_dir, url=opt.url_dir)
    #save_pass(reduced_data, pass_data_dir)

    return reduced_data


def save_pass(telem, pass_data_dir):
    pass_save = {}
    for ttype in ('aca_temp', 'ccd_temp', 'dac'):
        pass_save[ttype] = dict(min=np.min(telem[ttype]),
                                max=np.max(telem[ttype]),
                                mean=np.mean(telem[ttype]))
    rep_file = open(os.path.join(pass_data_dir, 'pass.json'), 'w')
    rep_file.write(json.dumps(pass_save, sort_keys=True, indent=4))
    rep_file.close()



def month_stats_and_plots(start, opt, redo=False):
    """
    Make summary plots and statistics reports for months

    :param lookbackdays: N days to go back to define first month to rebuild
    :param redo: remake plots if true

    """

    if not os.path.exists(opt.web_dir):
        os.path.makedirs(opt.web_dir)
    toptable = open(os.path.join(opt.web_dir, 'toptable.htm'), 'w')
    toptable.write("<TABLE BORDER=1>\n")
    year_dirs = glob.glob(os.path.join(opt.data_dir, 'PASS_DATA', '*'))
    year_dirs.sort()
    for year_dir in year_dirs:
        match_year = re.match(".*(\d{4})$", year_dir)
        toptable.write("<TR><TD>%d</TD>" % int(match_year.group(1)))
        pass_dirs = glob.glob(os.path.join(year_dir, '*'))
        months = {}
        pass_dirs.sort()
        for pass_dir in pass_dirs:
            match_date = re.search(
                "(\d{4}:\d{3}:\d{2}:\d{2}:\d{2}\.\d{3})", pass_dir)
            obsdate = DateTime(match_date.group(1)).mxDateTime
            month = "%04d-M%02d" % (obsdate.year, obsdate.month)
            try:
                months[month].append(pass_dir)
            except KeyError:
                months[month] = [pass_dir]
        for month in sorted(months.keys()):

            month_range = Ska.report_ranges.timerange(month)
            log.info('working in %s' % month)
            toptable.write("<TD><A HREF=\"%s/SUMMARY_DATA/%s\">%s</TD>"
                           % (opt.url_dir, month, month))

            month_data_dir = os.path.join(opt.data_dir, 'SUMMARY_DATA', month)
            month_web_dir = os.path.join(opt.web_dir, 'SUMMARY_DATA', month)
            pass_file = 'pass_list.txt'
            if not os.path.exists(month_data_dir):
                os.makedirs(month_data_dir)
            if not os.path.exists(month_web_dir):
                os.makedirs(month_web_dir)
            pf = open(os.path.join(month_data_dir, pass_file), 'w')
            for pass_dir in months[month]:
                pf.write("%s\n" % pass_dir)
            pf.close()

            # only bother with recent passes unless we are in remake mode
            if (month_range['start'] >= start) or redo:

                tfig = {}
                tfig['dacvsdtemp'] = plt.figure(num=5, figsize=(4, 3))
                tfig['dac'] = plt.figure(num=6, figsize=(4, 3))
                tfig['aca_temp'] = plt.figure(num=7, figsize=(4, 3))
                tfig['ccd_temp'] = plt.figure(num=8, figsize=(4, 3))
                tfig['ccd_month'] = plt.figure(num=9, figsize=(8, 3))

                passlist = open(os.path.join(month_web_dir,
                                             'passlist.htm'), 'w')
                passlist.write("<TABLE>\n")
                passdates = []
                temp_range = dict(aca_temp=dict(max=None,
                                                min=None),
                                  ccd_temp=dict(max=None,
                                                min=None))

                for pass_dir in months[month]:
                    match_date = re.search(
                        "(\d{4}:\d{3}:\d{2}:\d{2}:\d{2}\.\d{3})", pass_dir)
                    passdate = match_date.group(1)
                    passdates.append(passdate)
                    mxpassdate = DateTime(passdate).mxDateTime

                    try:
                        PASS_DATA = os.path.join(opt.data_dir, 'PASS_DATA')
                        pass_tail_dir = re.sub(
                            "%s/" % PASS_DATA, '', pass_dir)
                        telem = per_pass_tasks(pass_tail_dir, opt)
                        curr_color = pass_color_maker.next()
                        passlist.write(
                            "<TR><TD><A HREF=\"%s/PASS_DATA/%d/%s\">%s</A></TD>"
                            "<TD BGCOLOR=\"%s\">&nbsp;</TD></TR>\n"
                            % (opt.url_dir,
                               mxpassdate.year,
                               passdate,
                               DateTime(telem['dac'].times[0]).date,
                               curr_color))
                        plt.figure(tfig['dacvsdtemp'].number)
                        # add randomization to dac
                        rand_dac = (telem['dac'].vals
                                    + np.random.random(len(telem['dac'].vals))
                                    - .5)
                        plt.plot(telem['aca_temp'].vals - telem['ccd_temp'].vals,
                                 rand_dac,
                                 color=curr_color, marker='.', markersize=.5)
                        for ttype in ('aca_temp', 'ccd_temp', 'dac'):
                            plt.figure(tfig[ttype].number)
                            plot_cxctime([DateTime(passdate).secs,
                                          DateTime(passdate).secs],
                                         [telem[ttype].vals.mean(),
                                          telem[ttype].vals.max()],
                                         color=curr_color, linestyle='-',
                                         marker='^')
                            plot_cxctime([DateTime(passdate).secs,
                                          DateTime(passdate).secs],
                                         [telem[ttype].vals.mean(),
                                          telem[ttype].vals.min()],
                                         color=curr_color, linestyle='-',
                                         marker='v')
                            plot_cxctime([DateTime(passdate).secs],
                                         [telem[ttype].vals.mean()],
                                         color=curr_color, marker='.',
                                         markersize=10)
                            if re.search('temp', ttype):
                                if (temp_range[ttype]['min'] is None
                                    or (temp_range[ttype]['min']
                                        > telem[ttype].vals.min())):
                                    temp_range[ttype]['min'] = telem[ttype].vals.min()
                                if (temp_range[ttype]['max'] is None
                                    or (temp_range[ttype]['max']
                                        < telem[ttype].vals.max())):
                                    temp_range[ttype]['max'] = telem[ttype].vals.max()

                    except MissingDataError:
                        print "skipping %s" % pass_dir

                passlist.write("</TABLE>\n")
                passlist.close()

                f = plt.figure(tfig['dacvsdtemp'].number)
                plt.ylim(characteristics.dacvsdtemp_plot['ylim'])
                plt.xlim(characteristics.dacvsdtemp_plot['xlim'])
                plt.ylabel('TEC DAC Control Level')
                plt.xlabel('ACA temp - CCD temp (C)')
                f.subplots_adjust(bottom=0.2, left=0.2)
                plt.savefig(os.path.join(month_web_dir, 'dacvsdtemp.png'))
                plt.close(f)

                time_pad = .1
                f = plt.figure(tfig['aca_temp'].number)
                plt.ylabel('ACA temp (C)')
                f.subplots_adjust(left=0.2)
                plt.ylim(min(characteristics.aca_temp_plot['ylim'][0],
                             temp_range['aca_temp']['min']),
                         max(characteristics.aca_temp_plot['ylim'][1],
                             temp_range['aca_temp']['max']))
                curr_xlims = plt.xlim()
                dxlim = curr_xlims[1] - curr_xlims[0]
                plt.xlim(curr_xlims[0] - time_pad * dxlim,
                         curr_xlims[1] + time_pad * dxlim)
                plt.savefig(os.path.join(month_web_dir, 'aca_temp.png'))
                plt.close(f)

                f = plt.figure(tfig['ccd_temp'].number)
                plt.ylabel('CCD temp (C)')
                plt.ylim(min(characteristics.ccd_temp_plot['ylim'][0],
                             temp_range['ccd_temp']['min']),
                         max(characteristics.ccd_temp_plot['ylim'][1],
                             temp_range['ccd_temp']['max']))
                f.subplots_adjust(left=0.2)
                curr_xlims = plt.xlim()
                dxlim = curr_xlims[1] - curr_xlims[0]
                plt.xlim(curr_xlims[0] - time_pad * dxlim,
                         curr_xlims[1] + time_pad * dxlim)
                plt.savefig(os.path.join(month_web_dir, 'ccd_temp.png'))
                plt.close(f)

                f = plt.figure(tfig['dac'].number)
                plt.ylim(characteristics.dac_plot['ylim'])
                plt.ylabel('TEC DAC Control Level')
                curr_xlims = plt.xlim()
                dxlim = curr_xlims[1] - curr_xlims[0]
                plt.xlim(curr_xlims[0] - time_pad * dxlim,
                         curr_xlims[1] + time_pad * dxlim)
                f.subplots_adjust(left=0.2)
                plt.savefig(os.path.join(month_web_dir, 'dac.png'))
                plt.close(f)

                f = plt.figure(tfig['ccd_month'].number)

                telem = fetch.MSID('AACCCDPT',
                                   DateTime(passdates[0]).secs - 86400,
                                   DateTime(passdates[-1]).secs + 86400)
                ccd_temps = telem.vals - 273.15
                # cut out nonsense bad data using the ccd_temp filter
                # in characteristics
                filters = characteristics.telem_chomp_limits
                type = 'ccd_temp'
                goodfilt = ((ccd_temps <= filters[type]['max'])
                            & (ccd_temps >= filters[type]['min']))
                goods = np.flatnonzero(goodfilt)
                bads = np.flatnonzero(goodfilt == False)
                for bad in bads:
                    log.info("filtering %s,%s,%6.2f" %
                             (DateTime(telem.times[bad]).date,
                              'AACCCDPT',
                              ccd_temps[bad]))
                # Filter in place
                ccd_temps = ccd_temps[goods]
                ccd_times = telem.times[goods]
                model_ccd_temp = aca_ccd_model(DateTime(passdates[0]).secs - 86400,
                                               DateTime(passdates[-1]).secs + 86400,
                                               np.mean(ccd_temps[0:10]))
                plot_cxctime(ccd_times, ccd_temps, 'k.')
                plot_cxctime(model_ccd_temp.times,
                             model_ccd_temp.comp['aacccdpt'].mvals,
                             'b.', markersize=2)
                plt.ylim(min(characteristics.ccd_temp_plot['ylim'][0],
                             temp_range['ccd_temp']['min'],
                             model_ccd_temp.comp['aacccdpt'].mvals.min()),
                         max(characteristics.ccd_temp_plot['ylim'][1],
                             temp_range['ccd_temp']['max'],
                             model_ccd_temp.comp['aacccdpt'].mvals.max()))
                plt.ylabel('CCD Temp (C)')
                plt.savefig(os.path.join(month_web_dir, 'ccd_temp_all.png'))
                plt.close(f)

                next_month = Ska.report_ranges.get_next(month_range)
                next_string = '%d-%s' % (next_month['year'],
                                         next_month['subid'])
                prev_month = Ska.report_ranges.get_prev(month_range)
                prev_string = '%d-%s' % (prev_month['year'],
                                         prev_month['subid'])

                month_index = os.path.join(month_web_dir, 'index.html')
                log.info("making %s" % month_index)
                month_template = jinja_env.get_template(
                    'month_index_template.html')
                page = month_template.render(task={'url': opt.url_dir,
                                                   'next': next_string,
                                                   'prev': prev_string},
                                             month={'name': month})
                month_fh = open(month_index, 'w')
                month_fh.write(page)
                month_fh.close()

        toptable.write("</TR>\n")

    toptable.write("</TABLE>\n")
    toptable.close()

    topindex_template_file = os.path.join(
        TASK_SHARE, 'templates', 'top_index_template.html')
    topindex_template = open(topindex_template_file).read()
    topindex = open(os.path.join(opt.web_dir, 'index.html'), 'w')
    topindex.writelines(topindex_template)
    topindex.close()


def main():

    (opt, args) = get_options()
    ch = logging.StreamHandler()
    ch.setLevel(logging.WARN)
    if opt.verbose == 2:
        ch.setLevel(logging.DEBUG)
    if opt.verbose == 0:
        ch.setLevel(logging.ERROR)

    has_stream = None
    for h in log.handlers:
        if isinstance(h, logging.StreamHandler):
            has_stream = True
    if not has_stream:
        log.addHandler(ch)

    PASS_DATA = os.path.join(opt.data_dir, 'PASS_DATA')
    if not os.path.exists(PASS_DATA):
        os.makedirs(PASS_DATA)

    nowdate = DateTime(time.time(), format='unix').mxDateTime
    if opt.start_time is None:
        nowminus = nowdate - mx.DateTime.DateTimeDeltaFromDays(opt.days_back)
    else:
        nowminus = DateTime(opt.start_time).mxDateTime
    last_month_start = mx.DateTime.DateTime(nowminus.year, nowminus.month, 1)

    log.info("---------- Perigee Pass Plots ran at %s ----------" % nowdate)
    log.info("Processing %s to %s" % (last_month_start, nowdate))
    pass_dirs = retrieve_perigee_telem(start=nowminus, pass_data_dir=PASS_DATA)
    pass_dirs.sort()
    for pass_dir in pass_dirs:
        try:
            pass_tail_dir = re.sub("%s/" % PASS_DATA, '', pass_dir)
            telem = per_pass_tasks(pass_tail_dir, opt)
        except MissingDataError:
            print "skipping %s" % pass_dir
    month_stats_and_plots(start=last_month_start,
                          opt=opt)


if __name__ == '__main__':
    main()
