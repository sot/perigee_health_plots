import glob
from pathlib import Path
from optparse import OptionParser
import os
import re
import numpy as np
import numpy.ma as ma
import logging
from logging.handlers import SMTPHandler
from itertools import cycle
from jinja2 import Template
import json
import matplotlib
import matplotlib.pyplot as plt
from astropy.table import Table

from kadi import events
import kadi.commands.states as kadi_states
from Chandra.Time import DateTime
import Ska.Shell
import Ska.report_ranges
from Ska.engarchive import fetch
from mica.archive import aca_hdr3
from Ska.Matplotlib import plot_cxctime
import xija
from xija.get_model_spec import get_xija_model_spec
import proseco.characteristics


plt.rcParams['lines.markeredgewidth'] = 0


# Colors for plots: red, green, blue, magenta, cyan, orange, purple... maybe
PLOT_COLORS = ['#ff0000', '#00ff00', '#0000ff',
               '#ff00ff', '#00ffff', '#ff6600',
               '#6600ff']

# Break up telem in chunks of time_interval seconds
TIME_INTERVAL = 20.0

# Require min_samples per time_interval
MIN_SAMPLES = 5

# if telem values exceed these limits, cut the values
TELEM_CHOMP_LIMITS = {'dac': {'max': 550},
                      'ccd_temp': {'min': -35,
                                   'max': 50},
                      'aca_temp': {'max': 60,
                                   'min': 5}}

# If telem values exceed these limits send a warning
# This is intended to be planning limit +1C
TELEM_LIMITS = {'ccd_temp': {'max': proseco.characteristics.aca_t_ccd_planning_limit + 1}}

# Plot ranges
DAC_PLOT = {'ylim': (460, 515)}
DACVSDTEMP_PLOT = {'ylim': (460, 515),
                   'xlim': (37, 45)}
ACA_TEMP_PLOT = {'ylim': (9, 40)}
CCD_TEMP_PLOT = {'ylim': (-16, -3)}


log = logging.getLogger()
log.setLevel(logging.DEBUG)

# emails...
smtp_handler = SMTPHandler('localhost',
                           'aca@head.cfa.harvard.edu',
                           'aca@cfa.harvard.edu',
                           'perigee health mon')

smtp_handler.setLevel(logging.WARN)
has_smtp = None
for h in log.handlers:
    if isinstance(h, logging.handlers.SMTPHandler):
        has_smtp = True
if not has_smtp:
    log.addHandler(smtp_handler)

pass_color_maker = cycle(PLOT_COLORS)
obsid_color_maker = cycle(PLOT_COLORS)

task = 'perigee_health_plots'
SKA = os.environ['SKA']
TASK_SHARE = os.path.join(os.environ['SKA'], 'share', 'perigee_health_plots')


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
    state_keys = ['obsid', 'pitch', 'q1', 'q2', 'q3', 'q4', 'eclipse']
    states = kadi_states.get_states(start=tstart, stop=tstop,
                                    state_keys=state_keys, merge_identical=True)

    model_spec, model_version = get_xija_model_spec('aca')
    model = xija.ThermalModel('aca', start=tstart, stop=tstop,
                              model_spec=model_spec)
    times = np.array([states['tstart'], states['tstop']])
    model.comp['pitch'].set_data(states['pitch'], times)
    model.comp['eclipse'].set_data(states['eclipse'] != 'DAY', times)
    model.comp['aca0'].set_data(init_temp, tstart)
    model.comp['aacccdpt'].set_data(init_temp, tstart)
    model.make()
    model.calc()
    return model, model_version


def retrieve_telem(start='2009:100:00:00:00.000',
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

    # Default tstop should be now
    if stop is None:
        tstop = DateTime()

    log.info("retrieve_telem(): Checking for current telemetry from %s"

             % tstart.date)

    pass_time_file = 'pass_times.txt'

    orbits = events.orbits.filter(tstart, tstop)
    pass_dirs = []

    for orbit in orbits:
        er_start = orbit.start
        er_stop = orbit.stop
        log.debug("checking for %s orbit" % er_start)
        er_year = DateTime(er_start).year
        year_dir = os.path.join(pass_data_dir, "%s" % er_year)
        if not os.access(year_dir, os.R_OK):
            os.mkdir(year_dir)
        pass_dir = os.path.join(pass_data_dir, "%s" % er_year, er_start)
        if not os.access(pass_dir, os.R_OK):
            os.mkdir(pass_dir)
        pass_dirs.append(pass_dir)
        made_timefile = os.path.exists(os.path.join(pass_dir, pass_time_file))
        if made_timefile:
            pass_done = Table.read(
                os.path.join(pass_dir, pass_time_file), format='ascii')
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


def orbit_parse(pass_dir, min_samples=5, time_interval=20):
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

    log.info("orbit_parse(): parsing %s" % pass_dir)

    pass_time_file = 'pass_times.txt'
    if not os.path.exists(os.path.join(pass_dir, pass_time_file)):
        raise MissingDataError("Missing telem for pass %s" % pass_dir)
    pass_times = Table.read(os.path.join(pass_dir,
                                         pass_time_file), format='ascii')
    mintime = pass_times[0]['obsid_datestart']
    maxtime = pass_times[0]['obsid_datestop']

    hdr3 = aca_hdr3.MSIDset(['dac', 'ccd_temp', 'aca_temp'],
                            mintime, maxtime)

    parsed_telem = {'obsid': fetch.MSID('COBSRQID', mintime, maxtime),
                    'dac': hdr3['dac'],
                    'aca_temp': hdr3['aca_temp'],
                    'ccd_temp': hdr3['ccd_temp']}

    if not len(parsed_telem['ccd_temp'].vals):
        raise MissingDataError(
            f"No HDR3 data for pass {pass_times[0]['obsid_datestart']}")
    return parsed_telem


def get_telem_range(telem):

    # find the 5th and 95th percentiles
    sorted = np.sort(telem)
    ninety_five = sorted[int(len(sorted) * .95)]
    five = sorted[int(len(sorted) * .05)]
    # mean = telem.mean()
    # 10% = (ninety_five - five)/9.
    # min = five - 10%
    # max = ninety_five + 10%
    return [five - ((ninety_five - five) / 9.),
            ninety_five + ((ninety_five - five) / 9.)]


def plot_orbit(telem, pass_dir, url, redo=False):
    """
    Make plots of of TEC DAC level and ACA and CCD temperatures from
    8x8 image telemetry.
    Create html for the per-orbit page to contain the figures.

    :param telem: telem dict as created by orbit_parse()
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
    obs_times = [telem['obsid'].times[telem['obsid'].vals == obsid][0]
                 for obsid in uniq_obs]

    # in time order
    for obsid in np.array(uniq_obs)[np.argsort(obs_times)]:
        obsmatch = np.flatnonzero(telem['obsid'].vals == obsid)
        curr_color = next(obsid_color_maker)
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

        rand_obs_dac = (telem['dac'].vals[time_idx]
                        + np.random.random(len(telem['dac'].vals[time_idx])) - .5)
        dtemp = telem['aca_temp'].vals[time_idx] - telem['ccd_temp'].vals[time_idx]

        # Only plot if there's at least 1 unmasked sample
        if len(np.flatnonzero(~dtemp.mask)):
            plt.figure(tfig['dacvsdtemp'].number)
            plt.plot(dtemp,
                     rand_obs_dac,
                     color=curr_color,
                     marker='.', linestyle='None')
        if len(np.flatnonzero(~telem['dac'].vals[time_idx].mask)):
            plt.figure(tfig['dac'].number)
            plot_cxctime(telem['dac'].times[time_idx],
                         rand_obs_dac,
                         color=curr_color, marker='.', linestyle='None')
        if len(np.flatnonzero(~telem['aca_temp'].vals[time_idx].mask)):
            plt.figure(tfig['aca_temp'].number)
            plot_cxctime(telem['aca_temp'].times[time_idx],
                         telem['aca_temp'].vals[time_idx],
                         color=curr_color, marker='.', linestyle='None')
        if len(np.flatnonzero(~telem['ccd_temp'].vals[time_idx].mask)):
            plt.figure(tfig['ccd_temp'].number)
            plot_cxctime(telem['ccd_temp'].times[time_idx],
                         telem['ccd_temp'].vals[time_idx],
                         color=curr_color, marker='.', linestyle='None')

    obslist.write("</TABLE>\n")
    obslist.close()

    aca_temp_lims = get_telem_range(telem['aca_temp'].vals)
    ccd_temp_lims = get_telem_range(telem['ccd_temp'].vals)

    h = plt.figure(tfig['dacvsdtemp'].number)
    plt.ylim(DACVSDTEMP_PLOT['ylim'])
    plt.ylabel('TEC DAC Control Level')
    plt.xlim(min(DACVSDTEMP_PLOT['xlim'][0],
                 np.min(dtemp) - .5),
             max(DACVSDTEMP_PLOT['xlim'][1],
                 np.max(dtemp) + .5))
    plt.xlabel("ACA temp - CCD temp (C)\n\n")
    h.subplots_adjust(bottom=0.2, left=.2)
    plt.grid(True)
    plt.savefig(os.path.join(pass_dir, 'dacvsdtemp.png'))
    plt.close(h)

    h = plt.figure(tfig['dac'].number)
    plt.ylim(DAC_PLOT['ylim'])
    plt.ylabel('TEC DAC Control Level')
    h.subplots_adjust(left=.2)
    plt.grid(True)
    plt.savefig(os.path.join(pass_dir, 'dac.png'))
    plt.close(h)

    h = plt.figure(tfig['aca_temp'].number)
    plt.ylabel('ACA temp (C)')
    plt.ylim(min(ACA_TEMP_PLOT['ylim'][0],
                 aca_temp_lims[0]),
             max(ACA_TEMP_PLOT['ylim'][1],
                 aca_temp_lims[1]))
    h.subplots_adjust(left=0.2)
    plt.grid(True)
    plt.savefig(os.path.join(pass_dir, 'aca_temp.png'))
    plt.close(h)

    h = plt.figure(tfig['ccd_temp'].number)
    h.subplots_adjust(left=0.2)
    plt.ylim(min(CCD_TEMP_PLOT['ylim'][0],
                 ccd_temp_lims[0]),
             max(CCD_TEMP_PLOT['ylim'][1],
                 ccd_temp_lims[1]))
    plt.ylabel('CCD temp (C)')
    plt.grid(True)
    plt.savefig(os.path.join(pass_dir, 'ccd_temp.png'))
    plt.close(h)

    file_dir = Path(__file__).parent
    pass_index_template = Template(open(file_dir / 'pass_index_template.html',
                                        'r').read())
    pass_index_page = pass_index_template.render(task={'url': url})
    pass_fh = open(os.path.join(pass_dir, 'index.html'), 'w')
    pass_fh.write(pass_index_page)
    pass_fh.close()


def per_pass_tasks(pass_tail_dir, opt):

    pass_data_dir = os.path.join(opt.data_dir, 'PASS_DATA', pass_tail_dir)
    if not os.path.exists(pass_data_dir):
        os.makedirs(pass_data_dir)
    reduced_data = orbit_parse(pass_data_dir)

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

    # Cut out nonsense bad data
    types = ['aca_temp', 'ccd_temp', 'dac']
    filters = TELEM_CHOMP_LIMITS
    for type in filters.keys():
        if 'max' in filters[type]:
            maxbads = np.flatnonzero(reduced_data[type].vals > filters[type]['max'])
            for bad in maxbads:
                log.info("filtering %s,%s,%6.2f" %
                         (DateTime(reduced_data[type].times[bad]).date,
                          type,
                          reduced_data[type].vals[bad]))

            for ttype in types:
                reduced_data[ttype].vals.mask[maxbads] = ma.masked
        if 'min' in filters[type]:
            minbads = np.flatnonzero(reduced_data[type].vals < filters[type]['min'])
            for bad in minbads:
                log.info("filtering %s,%s,%6.2f" %
                         (DateTime(reduced_data[type].times[bad]).date,
                          type,
                          reduced_data[type].vals[bad]))
            for ttype in types:
                reduced_data[ttype].vals.mask[maxbads] = ma.masked

    # Run limit checks
    limits = TELEM_LIMITS
    pass_url = opt.web_server + os.path.join(
        opt.url_dir, 'PASS_DATA', pass_tail_dir)
    for type in limits.keys():
        if 'max' in limits[type]:
            if ((max(reduced_data[type].vals) > limits[type]['max'])
                and not os.path.exists(
                    os.path.join(pass_data_dir, 'warned.txt'))):
                warn_text = (
                    "Limit Exceeded, %s of %6.2f is > %6.2f \n at %s"
                    % (type,
                       max(reduced_data[type].vals),
                       limits[type]['max'],
                       pass_url))
                log.warning(warn_text)
                warn_file = open(
                    os.path.join(pass_data_dir, 'warned.txt'), 'w')
                warn_file.write(warn_text)
                warn_file.close()

        if 'min' in limits[type]:
            if ((min(reduced_data[type].vals) < limits[type]['min'])
                and not os.path.exists(
                    os.path.join(pass_data_dir, 'warned.txt'))):
                warn_text = (
                    "Limit Exceeded, %s of %6.2f is < %6.2f \n at %s"
                    % (type,
                       min(reduced_data[type].vals),
                       limits[type]['min'],
                       pass_url))
                log.warning(warn_text)
                warn_file = open(
                    os.path.join(pass_data_dir, 'warned.txt'), 'w')
                warn_file.write(warn_text)
                warn_file.close()

    plot_orbit(reduced_data, pass_web_dir, url=opt.url_dir)
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
        match_year = re.match(r".*(\d{4})$", year_dir)
        toptable.write("<TR><TD>%d</TD>" % int(match_year.group(1)))
        pass_dirs = glob.glob(os.path.join(year_dir, '*'))
        months = {}
        pass_dirs.sort()
        for pass_dir in pass_dirs:
            match_date = re.search(
                r"(\d{4}:\d{3}:\d{2}:\d{2}:\d{2}\.\d{3})", pass_dir)
            obsdate = DateTime(match_date.group(1))
            month = "%04d-M%02d" % (obsdate.year, obsdate.mon)
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
            if (DateTime(month_range['start']).secs >= start.secs) or redo:

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
                temp_range = dict(aca_temp=dict(max=ACA_TEMP_PLOT['ylim'][1],
                                                min=ACA_TEMP_PLOT['ylim'][0]),
                                  ccd_temp=dict(max=CCD_TEMP_PLOT['ylim'][1],
                                                min=CCD_TEMP_PLOT['ylim'][0]),
                                  dtemp=dict(max=DACVSDTEMP_PLOT['xlim'][1],
                                             min=DACVSDTEMP_PLOT['xlim'][0]))

                for pass_dir in months[month]:
                    match_date = re.search(
                        r"(\d{4}:\d{3}:\d{2}:\d{2}:\d{2}\.\d{3})", pass_dir)
                    passdate = match_date.group(1)
                    passdates.append(passdate)
                    ctpassdate = DateTime(passdate)

                    try:
                        PASS_DATA = os.path.join(opt.data_dir, 'PASS_DATA')
                        pass_tail_dir = re.sub(
                            "%s/" % PASS_DATA, '', pass_dir)
                        telem = per_pass_tasks(pass_tail_dir, opt)
                        curr_color = next(pass_color_maker)
                        passlist.write(
                            "<TR><TD><A HREF=\"%s/PASS_DATA/%d/%s\">%s</A></TD>"
                            "<TD BGCOLOR=\"%s\">&nbsp;</TD></TR>\n"
                            % (opt.url_dir,
                               ctpassdate.year,
                               passdate,
                               DateTime(telem['dac'].times[0]).date,
                               curr_color))
                        plt.figure(tfig['dacvsdtemp'].number)

                        # Add randomization to dac
                        rand_dac = (telem['dac'].vals
                                    + np.random.random(len(telem['dac'].vals))
                                    - .5)
                        plt.plot(telem['aca_temp'].vals - telem['ccd_temp'].vals,
                                 rand_dac,
                                 color=curr_color, marker='.', markersize=.5)
                        dtemp = telem['aca_temp'].vals - telem['ccd_temp'].vals
                        if (temp_range['dtemp']['min'] is None
                                or (temp_range['dtemp']['min'] > np.min(dtemp))):
                            temp_range['dtemp']['min'] = np.min(dtemp)
                        if (temp_range['dtemp']['max'] is None
                                or (temp_range['dtemp']['max'] < np.max(dtemp))):
                            temp_range['dtemp']['max'] = np.max(dtemp)
                        for ttype in ('aca_temp', 'ccd_temp', 'dac'):
                            if telem[ttype].vals.mean() is ma.masked:
                                raise MissingDataError("Data for pass %s is masked" % pass_dir)
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
                        log.info("skipping %s" % pass_dir)

                passlist.write("</TABLE>\n")
                passlist.close()

                f = plt.figure(tfig['dacvsdtemp'].number)
                plt.ylim(DACVSDTEMP_PLOT['ylim'])
                plt.xlim(min(DACVSDTEMP_PLOT['xlim'][0],
                             -0.5 + temp_range['dtemp']['min']),
                         max(DACVSDTEMP_PLOT['xlim'][1],
                             +0.5 + temp_range['dtemp']['max']))
                plt.ylabel('TEC DAC Control Level')
                plt.xlabel('ACA temp - CCD temp (C)')
                f.subplots_adjust(bottom=0.2, left=0.2)
                plt.grid(True)
                plt.savefig(os.path.join(month_web_dir, 'dacvsdtemp.png'))
                plt.close(f)

                time_pad = .1
                f = plt.figure(tfig['aca_temp'].number)
                plt.ylabel('ACA temp (C)')
                f.subplots_adjust(left=0.2)
                plt.ylim(min(ACA_TEMP_PLOT['ylim'][0],
                             temp_range['aca_temp']['min']),
                         max(ACA_TEMP_PLOT['ylim'][1],
                             temp_range['aca_temp']['max']))
                curr_xlims = plt.xlim()
                dxlim = curr_xlims[1] - curr_xlims[0]
                plt.xlim(curr_xlims[0] - time_pad * dxlim,
                         curr_xlims[1] + time_pad * dxlim)
                plt.grid(True)
                plt.savefig(os.path.join(month_web_dir, 'aca_temp.png'))
                plt.close(f)

                f = plt.figure(tfig['ccd_temp'].number)
                plt.ylabel('CCD temp (C)')
                plt.ylim(min(CCD_TEMP_PLOT['ylim'][0],
                             temp_range['ccd_temp']['min']),
                         max(CCD_TEMP_PLOT['ylim'][1],
                             temp_range['ccd_temp']['max']))
                f.subplots_adjust(left=0.2)
                curr_xlims = plt.xlim()
                dxlim = curr_xlims[1] - curr_xlims[0]
                plt.xlim(curr_xlims[0] - time_pad * dxlim,
                         curr_xlims[1] + time_pad * dxlim)
                plt.grid(True)
                plt.savefig(os.path.join(month_web_dir, 'ccd_temp.png'))
                plt.close(f)

                f = plt.figure(tfig['dac'].number)
                plt.ylim(DAC_PLOT['ylim'])
                plt.ylabel('TEC DAC Control Level')
                curr_xlims = plt.xlim()
                dxlim = curr_xlims[1] - curr_xlims[0]
                plt.xlim(curr_xlims[0] - time_pad * dxlim,
                         curr_xlims[1] + time_pad * dxlim)
                f.subplots_adjust(left=0.2)
                plt.grid(True)
                plt.savefig(os.path.join(month_web_dir, 'dac.png'))
                plt.close(f)

                f = plt.figure(tfig['ccd_month'].number)

                telem = fetch.MSID('AACCCDPT',
                                   DateTime(passdates[0]).secs - 86400,
                                   DateTime(passdates[-1]).secs + 86400)
                ccd_temps = telem.vals - 273.15

                # Cut out nonsense bad data using the ccd_temp filter
                filters = TELEM_CHOMP_LIMITS
                type = 'ccd_temp'
                goodfilt = ((ccd_temps <= filters[type]['max'])
                            & (ccd_temps >= filters[type]['min']))
                goods = np.flatnonzero(goodfilt)
                bads = np.flatnonzero(~goodfilt)
                for bad in bads:
                    log.info("filtering %s,%s,%6.2f" %
                             (DateTime(telem.times[bad]).date,
                              'AACCCDPT',
                              ccd_temps[bad]))

                # Filter in place
                ccd_temps = ccd_temps[goods]
                ccd_times = telem.times[goods]

                # Save some trouble and only run the model when telem is available
                eclipse_data_range = fetch.get_time_range('AOECLIPS')
                model_end_time = np.min([DateTime(passdates[-1]).secs + 86400,
                                         eclipse_data_range[1]])
                model_ccd_temp, model_version = aca_ccd_model(
                    DateTime(passdates[0]).secs - 86400,
                    model_end_time,
                    np.mean(ccd_temps[0:10]))
                plot_cxctime(ccd_times, ccd_temps, 'b.', markersize=2.5,
                             label='telem')
                plot_cxctime(model_ccd_temp.times,
                             model_ccd_temp.comp['aacccdpt'].mvals,
                             'r', label='model')
                plt.ylim(min(CCD_TEMP_PLOT['ylim'][0],
                             temp_range['ccd_temp']['min'] - 1,
                             model_ccd_temp.comp['aacccdpt'].mvals.min() - 1),
                         max(CCD_TEMP_PLOT['ylim'][1],
                             temp_range['ccd_temp']['max'] + 1,
                             model_ccd_temp.comp['aacccdpt'].mvals.max() + 1))
                plt.title(f'ACA model {model_version} and telemetry')
                plt.legend()
                plt.ylabel('CCD Temp (C)')
                plt.grid(True)
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

                file_dir = Path(__file__).parent
                month_template = Template(
                    open(file_dir / 'month_index_template.html',
                         'r').read())
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

    file_dir = Path(__file__).parent

    # This one isn't jinja2, it uses a virtual include
    topindex_template = open(file_dir / 'top_index_template.html',
                             'r').read()
    topindex = open(os.path.join(opt.web_dir, 'index.html'), 'w')
    topindex.writelines(topindex_template)
    topindex.close()


def main():

    matplotlib.use("Agg")

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

    nowdate = DateTime()
    if opt.start_time is None:
        nowminus = nowdate - int(opt.days_back)
    else:
        nowminus = DateTime(opt.start_time)

    last_month_start = DateTime("{}-{:02d}-01 00:00:00.000".format(
        nowminus.year, nowminus.mon))

    log.info("---------- Perigee Pass Plots ran at %s ----------" % nowdate.date)
    log.info("Processing %s to %s" % (last_month_start.date, nowdate.date))
    pass_dirs = retrieve_telem(start=nowminus, pass_data_dir=PASS_DATA)
    pass_dirs.sort()
    for pass_dir in pass_dirs:
        try:
            pass_tail_dir = re.sub("%s/" % PASS_DATA, '', pass_dir)
            per_pass_tasks(pass_tail_dir, opt)
        except MissingDataError:
            log.info("skipping %s" % pass_dir)
    month_stats_and_plots(start=last_month_start,
                          opt=opt)


if __name__ == '__main__':
    main()
