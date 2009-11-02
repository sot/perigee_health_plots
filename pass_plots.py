#!/usr/bin/env python
import glob
from optparse import OptionParser
import os
import time
import cPickle
import re
import numpy as np
import logging
from logging.handlers import SMTPHandler
from itertools import count, izip, cycle
import mx.DateTime
from Chandra.Time import DateTime
from Ska.DBI import DBI
import Ska.Shell

# Matplotlib setup
# Use Agg backend for command-line (non-interactive) operation
import matplotlib
if __name__ == '__main__':
    matplotlib.use('Agg')
import matplotlib.pyplot as plt
from Ska.Matplotlib import cxctime2plotdate


log = logging.getLogger()
log.setLevel(logging.DEBUG)

# emails...                                                                                      
smtp_handler = logging.handlers.SMTPHandler('localhost',
                                           'jeanconn@head.cfa.harvard.edu',
                                           'jeanconn@head.cfa.harvard.edu',
                                           'load segment update')
smtp_handler.setLevel(logging.WARN)
log.addHandler(smtp_handler) 



colors = ['#ff0000', '#00ff00', '#0000ff',
          '#ff00ff', '#00ffff', '#ff6600',
          '#6600ff' ]
pass_color_maker = cycle(colors)
obsid_color_maker = cycle(colors)

#TASK_DATA = os.path.join(os.environ['SKA'], 'data', 'perigee_data')
TASK_DATA = '/proj/gads6/jeanproj/perigee_health_plots_dev'
TASK_DIR = '/proj/sot/ska/www/ASPECT/perigee_health_plots'
URL = 'http://cxc.harvard.edu/mta/ASPECT/perigee_health_plots'
PASS_DATA = os.path.join(TASK_DIR, 'PASS_DATA')
SUMMARY_DATA = os.path.join(TASK_DIR, 'SUMMARY_DATA')

# Django setup for template rendering
import django.template
import django.conf
if not django.conf.settings._target:
    try:
        django.conf.settings.configure()
    except RuntimeError, msg:
        print msg
        


def get_options():
    parser = OptionParser(usage='pass_plots.py [options]')
    parser.set_defaults()
    parser.add_option("-v", "--verbose",
                      type='int',
                      default=1,
                      help="Verbosity (0=quiet, 1=normal, 2=debug)",
                      )
    (opt,args) = parser.parse_args()
    return opt, args

# temporary custom plot_cxctime for non-interactive backends
# should be removed now that Ska.Matplotlib 0.04 is installed
def plot_cxctime(times, y, fig=None, **kwargs):
    """Make a date plot where the X-axis values are in CXC time.  If no ``fig``
    value is supplied then the current figure will be used (and created
    automatically if needed).  Any additional keyword arguments
    (e.g. ``fmt='b-'``) are passed through to the ``plot_date()`` function.

    :param times: CXC time values for x-axis (date)
    :param y: y values
    :param fig: pyplot figure object (optional)
    :param **kwargs: keyword args passed through to ``plot_date()``

    :rtype: ticklocs, fig, ax = tick locations, figure, and axes object.
    """
    if fig is None:
        fig = plt.gcf()

    ax = fig.gca()
    import Ska.Matplotlib
    ax.plot_date(Ska.Matplotlib.cxctime2plotdate(times), y, **kwargs)
    ticklocs = Ska.Matplotlib.set_time_ticks(ax)
    fig.autofmt_xdate()

    return ticklocs, fig, ax

def retrieve_perigee_telem(start='2009:100:00:00:00.000', 
                           stop=None,
                           redo=False):
    """
    Retrieve perigee pass and other 8x8 image telemetry.
    
    Telemetry is stored in directories named by datestart in the PASS_DATA directory.
    The file pass_times.txt in each directory contains the time range that 
    has been queried for 8x8 image data
    
    :param start: Chandra.Time compatible time for beginning of range 
    :param stop: Chandra.time compatible time for end of range
    :rtype: list of updated directories
    """

    tstart = DateTime(start)
    # default tstop should be now
    if stop is None:
        tstop=DateTime(time.time(), format='unix')

    log.info("retrieve_perigee_telem(): Checking for current telemetry from %s" % tstart.date)

    pass_data_dir = PASS_DATA
    pass_time_file = 'pass_times.txt'
    aca_db = DBI(dbi='sybase')
    obsids = aca_db.fetchall("SELECT obsid,obsid_datestart,obsid_datestop from observations " 
                             "where obsid_datestart > '%s' and obsid_datestart < '%s'" 
                             % (tstart.date,tstop.date));

    # find the ERs
    obs_is_er = np.zeros(len(obsids))
    obs_is_er[np.flatnonzero( obsids.obsid > 40000 )] = 1

    # step through the obsids and find the contiguous ER ranges
    # ( matrix logical operations for this broke and should be re-attempted )
    toggle = None
    er_starts_idx = []
    er_stops_idx = []
    for idx in range(0,len(obs_is_er)):
        if obs_is_er[idx] == 1:
            if toggle is None or toggle == 0:
                toggle = 1
                er_starts_idx.append(idx)
        else:
            if toggle == 1:
                toggle = 0
                er_stops_idx.append(idx)
    er_starts = DateTime( obsids[er_starts_idx].obsid_datestart )
    er_stops = DateTime( obsids[np.array(er_stops_idx) - 1].obsid_datestop )

    pass_dirs = []
    # for each ER chunk get telemetry (most of these will be perigee passes)
    for er_start, er_stop in izip( er_starts.date, er_stops.date):
        er_year = DateTime(er_start).mxDateTime.year
        year_dir = os.path.join(pass_data_dir, "%s" % er_year )
        if not os.access(year_dir, os.R_OK):
            os.mkdir(year_dir)
        pass_dir =  os.path.join(pass_data_dir, "%s" % er_year, er_start )
        pass_dirs.append(pass_dir)
        if not os.access(pass_dir, os.R_OK):
            os.mkdir(pass_dir)
        made_timefile = os.path.exists(os.path.join(pass_dir, pass_time_file))
        if redo is True or not made_timefile:
            log.info("get_perigee_telem.pl --tstart '%s' --tstop '%s' --dir '%s'" 
                     % (er_start, er_stop, pass_dir))
            Ska.Shell.bash_shell( "./get_perigee_telem.pl --tstart '%s' --tstop '%s' --dir '%s'" 
                                  % (er_start, er_stop, pass_dir) )
        #print pass_dir
            f = open(os.path.join(pass_dir, pass_time_file), 'w')
            f.write("obsid_datestart,obsid_datestop\n")
            f.write("%s,%s\n" % (er_start, er_stop))
            f.close()
            
    return pass_dirs


def perigee_parse( pass_dir, min_samples=5, time_interval=20 ):
    """
    Determine TEC DAC level and temperatures from available telemetry.  
    Create telemetry structure.
    
    For the supplied telem directory (pass_dir) read and concatenate the CCDM telemetry
    and the ACA0 telemetry (by slot).
    
    For each "time_interval" determine if the minimum number of telemetry samples 
    "min_samples" are supplied.
    Skip intervals which do not have the minimum number of samples in all slots.

    :param pass_dir: directory containing CCDM and ACA0 telemetry
    :param min_samples: int, minimum number of samples to be contained in time_interval 
    :param time_interval: int seconds, telemetry "chunking" interval
    :returns: reduced telemetry
    :rtype: dict
    """

    log.info("perigee_parse(): parsing %s" % pass_dir )

    pass_time_file = 'pass_times.txt'
    import Ska.Table
    import numpy as np
    pass_times = Ska.Table.read_ascii_table( os.path.join( pass_dir, pass_time_file))
    ccdm_files = sorted(glob.glob(os.path.join( pass_dir, "ccdm*")))
    for ccdm_file in ccdm_files:
        ccdm_table = Ska.Table.read_fits_table(ccdm_file)
        try:
            ccdm = np.append( ccdm, ccdm_table)
        except NameError:
            ccdm = ccdm_table

    aca0 = {}
    for slot in (0,1,2,6,7):
        aca_files = sorted(glob.glob(os.path.join( pass_dir, "aca*_%s_*" % slot )))
        for aca_file in aca_files:
            aca_table = Ska.Table.read_fits_table(aca_file)
            if aca_table.IMGRAW.shape[1] == 64:
                if aca0.has_key(slot):
                    aca0[slot] = np.append( aca0[slot], aca_table )
                else:
                    aca0[slot] = aca_table

    mintime = pass_times[0].obsid_datestart
    maxtime = pass_times[0].obsid_datestop

    # determine the time range contained by all the slots
    for slot in aca0.keys():
        minslottime = DateTime(aca0[slot]['TIME'].min()).date
        maxslottime = DateTime(aca0[slot]['TIME'].max()).date
        if minslottime > mintime:
            mintime = minslottime
        if maxslottime < maxtime:
            maxtime = maxslottime

    # calculate the number of intervals for the time range
    n_intervals = (DateTime(maxtime).secs - DateTime(mintime).secs)/time_interval

    result = {}
    # throw some stuff into a hash to have it handy later if needed
    result['info'] = { 'sample_interval_in_secs': time_interval,
                       'datestart' : mintime,
                       'datestop' : maxtime,
                       'min_required_samples' : min_samples,
                       'number_of_intervals' : n_intervals
                       }

    log.debug( result )

    parsed_telem = {}
    for t_idx in range(0,n_intervals):

        range_start = DateTime(mintime).secs + (t_idx * time_interval)
        range_end = range_start + time_interval
        ok = {}
        min_len = min_samples
        for slot in aca0.keys():
            ok[slot] = np.flatnonzero(
                ( aca0[slot]['TIME'] >= range_start)
                & ( aca0[slot]['TIME'] < range_end)
                & ( aca0[slot]['IMGRAW'].shape[1] == 64 )
                & ( aca0[slot]['QUALITY'] == 0 ))
            if len(ok[slot]) < min_len:
                min_len = len(ok[slot])

        # if we have at least the minimum number of samples
        if min_len == min_samples:
            ok_ccdm = np.flatnonzero(
                ( ccdm['TIME'] >= range_start )
                & ( ccdm['TIME'] < range_end ))

            products = {}
            obsids = ccdm[ok_ccdm]['COBSRQID']
            if len(obsids) == min_samples:
                products['obsids'] = obsids
            else:
                if len(obsids) < min_samples:
                    # fudge it if missing ccdm data
                    products['obsids'] = np.ones(min_samples) * obsids[0]
                else:
                    products['obsids'] = obsids[0:min_samples-1]

            products['dac'] = aca0[7]['HD3TLM76'][ok[7]] * 256. + aca0[7]['HD3TLM77'][ok[7]]
            products['time'] = aca0[7]['TIME'][ok[7]]
            #products['h066'] = aca0[0]['HD3TLM66'] * 256 + aca0[0]['HD3TLM67']
            #products['h072'] = aca0[0]['HD3TLM72'] * 256 + aca0[0]['HD3TLM73']
            #products['h074'] = aca0[0]['HD3TLM74'] * 256 + aca0[0]['HD3TLM75']
            #products['h174'] = aca0[1]['HD3TLM74'] * 256 + aca0[1]['HD3TLM75']
            #products['h176'] = aca0[1]['HD3TLM76'] * 256 + aca0[1]['HD3TLM77']
            #products['h262'] = aca0[2]['HD3TLM62'] * 256 + aca0[2]['HD3TLM63']
            #products['h264'] = aca0[2]['HD3TLM64'] * 256 + aca0[2]['HD3TLM65']
            #products['h266'] = aca0[2]['HD3TLM66'] * 256 + aca0[2]['HD3TLM67']
            #products['h272'] = aca0[2]['HD3TLM72'] * 256 + aca0[2]['HD3TLM73']
            #products['h274'] = aca0[2]['HD3TLM74'] * 256 + aca0[2]['HD3TLM75']
            #products['h276'] = aca0[2]['HD3TLM76'] * 256 + aca0[2]['HD3TLM77']
            products['aca_temp'] = aca0[7]['HD3TLM73'][ok[7]] * (1/256.) +  aca0[7]['HD3TLM72'][ok[7]]
            products['ccd_temp'] = ( (aca0[6]['HD3TLM76'][ok[6]] * 256.) + (aca0[6]['HD3TLM77'][ok[6]] - 65536. )) / 100.


            for prod_type in products.keys():
                try:
                    parsed_telem[prod_type] = np.append( parsed_telem[prod_type], products[prod_type])
                except KeyError:
                    parsed_telem[prod_type] = products[prod_type]

    return parsed_telem


def plot_pass( telem, pass_dir, redo=False ):
    """
    Make plots of of TEC DAC level and ACA and CCD temperatures from 8x8 image telemetry.
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
    if missing == 0 and redo==False:
        return 0
    log.info('making plots in %s' %  pass_dir)
    tfig = {}
    tfig['dacvsdtemp'] = plt.figure(num=1,figsize=(4,3))
    tfig['dac'] = plt.figure(num=2,figsize=(4,3))
    tfig['aca_temp'] = plt.figure(num=3,figsize=(4,3))
    tfig['ccd_temp'] = plt.figure(num=4,figsize=(4,3))

    obslist = open(os.path.join(pass_dir, 'obslist.htm'),'w')    
    obslist.write("<TABLE BORDER=1><TR><TH>obsid</TH><TH></TH><TH>start</TH><TH>stop</TH></TR>\n")
    uniq_obs = np.unique(telem['obsids'])

    # in reverse order for the ER table to look right
    for obsid in uniq_obs[::-1]:
        obsmatch = np.flatnonzero( telem['obsids'] == obsid )
        curr_color = obsid_color_maker.next()
        obslist.write("<TR><TD>%d</TD><TD BGCOLOR=\"%s\">&nbsp;</TD><TD>%s</TD><TD>%s</TD></TR>\n" 
                      % (obsid, 
                         curr_color,
                         DateTime(telem['time'][obsmatch[0]]).date,
                         DateTime(telem['time'][obsmatch[-1]]).date
                         ))
        plt.figure(tfig['dacvsdtemp'].number)
        rand_obs_dac = telem['dac'][obsmatch] + np.random.random(len(obsmatch))-.5
        plt.plot( telem['aca_temp'][obsmatch] - telem['ccd_temp'][obsmatch], 
              rand_obs_dac,
              color=curr_color, 
              marker='.', markersize=1)
        plt.figure(tfig['dac'].number) 
        plot_cxctime( telem['time'][obsmatch], 
                      rand_obs_dac,
                      color=curr_color, marker='.')
        plt.figure(tfig['aca_temp'].number)
        plot_cxctime( telem['time'][obsmatch], 
                      telem['aca_temp'][obsmatch], 
                      color=curr_color, marker='.')
        plt.figure(tfig['ccd_temp'].number)
        plot_cxctime( telem['time'][obsmatch], 
                      telem['ccd_temp'][obsmatch],
                      color=curr_color, marker='.')

    obslist.write("</TABLE>\n")
    obslist.close()

    h = plt.figure(tfig['dacvsdtemp'].number)
    plt.ylim(460,515)
    plt.ylabel('TEC DAC Control Level')
    plt.xlim(37,40)
    plt.xlabel("ACA temp - CCD temp (C)\n\n")
    h.subplots_adjust(bottom=0.2)
    plt.savefig(os.path.join(pass_dir, 'dacvsdtemp.png'))
    plt.close(h)

    h = plt.figure(tfig['dac'].number)
    plt.ylim(460,515)
    plt.ylabel('TEC DAC Control Level')
    plt.savefig(os.path.join(pass_dir, 'dac.png'))
    plt.close(h)

    h = plt.figure(tfig['aca_temp'].number)
    plt.ylabel('ACA temp (C)')
    plt.ylim(17,22)
    h.subplots_adjust(left=0.2)
    plt.savefig(os.path.join(pass_dir, 'aca_temp.png'))
    plt.close(h)

    h = plt.figure(tfig['ccd_temp'].number)
    h.subplots_adjust(left=0.2)
    plt.ylim(-20,-18)
    plt.ylabel('CCD temp (C)')
    plt.savefig(os.path.join(pass_dir, 'ccd_temp.png'))
    plt.close(h)

    django_context = django.template.Context({ 'task' : { 'url' : URL }})
    index = os.path.join(pass_dir, 'index.html')
    pass_index_template_file = os.path.join(TASK_DATA, 'pass_index_template.html')
    pass_index_template = open(pass_index_template_file).read()
    pass_index_template = re.sub(r' %}\n', ' %}', pass_index_template)
    pass_template = django.template.Template(pass_index_template)
    open(index, 'w').write(pass_template.render(django_context))

#    index = open(os.path.join(pass_dir, 'index.html'), 'w')
#    index.writelines(template)
#    index.close()
    


def per_pass_tasks( pass_dir ):
    tfile = 'telem.pickle'
    if not os.path.exists(os.path.join(pass_dir, tfile)):
        reduced_data = perigee_parse( pass_dir )
        f = open(os.path.join(pass_dir, tfile), 'w')
        cPickle.dump( reduced_data, f )
        f.close()
    else:
        f = open(os.path.join(pass_dir, tfile), 'r')
        reduced_data = cPickle.load(f)
        f.close()

    if not reduced_data.has_key('time'):
        raise ValueError("Error parsing telem for %s" % pass_dir)

    telem_time_file = 'telem_time.htm'
    if not os.path.exists(os.path.join(pass_dir, telem_time_file)):
        tf = open(os.path.join(pass_dir, telem_time_file), 'w')
        tf.write("<TABLE BORDER=1>\n")
        tf.write("<TR><TH>datestart</TH><TH>datestop</TH></TR>\n")
        tf.write("<TR><TD>%s</TD><TD>%s</TD></TR>\n" % 
                 ( DateTime(reduced_data['time'].min()).date, 
                   DateTime(reduced_data['time'].max()).date))
        tf.write("</TABLE>\n")
        tf.close()
    
    # figure out more filters later...
    filters = { 'dac' : { 'max' : 550 },
                'ccd_temp' : { 'min' : -35,
                               'max' : -5 },
                'aca_temp' : { 'max' : 50 },
                }

    for type in filters.keys():
        if filters[type].has_key('max'):
            goods = np.flatnonzero(reduced_data[type] <= filters[type]['max'])
            maxbads = np.flatnonzero(reduced_data[type] > filters[type]['max'])
            for bad in maxbads:
                logging.info("filtering %s,%s,%6.2f" % (  
                                               DateTime(reduced_data['time'][bad]).date,
                                               type,
                                               reduced_data[type][bad] ))
                
            for ttype in ('time', 'aca_temp', 'ccd_temp', 'dac'):
                reduced_data[ttype] = reduced_data[ttype][goods]
        if filters[type].has_key('min'):
            goods = np.flatnonzero(reduced_data[type] >= filters[type]['min'])
            minbads = np.flatnonzero(reduced_data[type] < filters[type]['min'])
            for bad in minbads:
                logging.info("filtering %s,%s,%6.2f" % ( 
                                               DateTime(reduced_data['time'][bad]).date,
                                               type,
                                               reduced_data[type][bad] ))
            for ttype in ('time', 'aca_temp', 'ccd_temp', 'dac'):
                reduced_data[ttype] = reduced_data[ttype][goods]


    return reduced_data


#def pass_stats_and_plots():
#    """
#    Make per-pass plots and statistic reports
#    """
#    pass_dirs = ['/proj/sot/ska/data/perigee_health_plots/PASS_DATA/2009/2009:190:00:21:16.226']
#    for pass_dir in pass_dirs:
#        telem = per_pass_tasks( pass_dir)
#        plot_pass( telem, pass_dir )


def month_stats_and_plots(lookbackdays=30, redo=False):
    """ 
    Make summary plots and statistics reports for months

    :param lookbackdays: number of days to go back to define first month to rebuild
    :param redo: remake plots if true

    """

    # 
    nowdate=DateTime(time.time(), format='unix').mxDateTime
    nowminus=nowdate - mx.DateTime.DateTimeDeltaFromDays(lookbackdays)
    last_month_start = mx.DateTime.DateTime(nowminus.year, nowminus.month, 1)
    
    pass_dirs = glob.glob(os.path.join(PASS_DATA, '*', '*'))
    months = {}
    pass_dirs.sort()
    for pass_dir in pass_dirs:
        match_date = re.search("(\d{4}:\d{3}:\d{2}:\d{2}:\d{2}\.\d{3})", pass_dir)
        obsdate = DateTime(match_date.group(1)).mxDateTime
        month = "%04d-%02d" % (obsdate.year, obsdate.month)
        try:
            months[month].append(pass_dir)
        except KeyError:
            months[month] = [ pass_dir ]

    toptable = open(os.path.join(TASK_DIR, 'toptable.htm'), 'w')
    toptable.write("<TABLE BORDER=1>\n")

    for month in sorted(months.keys()):

        toptable.write("<TR><TD><A HREF=\"%s/SUMMARY_DATA/%s\">%s</TD></TR>\n" 
                       % (URL, month, month))

        monthdir = os.path.join(SUMMARY_DATA, month)
        pass_file = 'pass_list.txt'
        if not os.path.exists(monthdir):
            os.makedirs(monthdir)
        
        pf = open( os.path.join(monthdir, pass_file), 'w')
        for pass_dir in months[month]:
            pf.write("%s\n" % pass_dir)
        pf.close()    

        month_split = re.search("(\d{4})-(\d{2})", month)
        month_start = mx.DateTime.DateTime(int(month_split.group(1)), int(month_split.group(2)), 1)
        # only bother with recent passes unless we are in remake mode
        if (month_start >= last_month_start) or (redo == True):
            
            tfig = {}
            tfig['dacvsdtemp'] = plt.figure(num=5,figsize=(4,3))
            tfig['dac'] = plt.figure(num=6,figsize=(4,3))
            tfig['aca_temp'] = plt.figure(num=7,figsize=(4,3))
            tfig['ccd_temp'] = plt.figure(num=8,figsize=(4,3))

            passlist = open(os.path.join(monthdir, 'passlist.htm'),'w')    
            passlist.write("<TABLE>\n")
            passdates = []

            for pass_dir in months[month]:
                match_date = re.search("(\d{4}:\d{3}:\d{2}:\d{2}:\d{2}\.\d{3})", pass_dir)
                passdate = match_date.group(1)
                passdates.append(passdate)
                mxpassdate = DateTime(passdate).mxDateTime
                try:
                    telem = per_pass_tasks(pass_dir)
                    curr_color = pass_color_maker.next()
                    passlist.write("<TR><TD><A HREF=\"%s/PASS_DATA/%d/%s\">%s</A></TD><TD BGCOLOR=\"%s\">&nbsp;</TD></TR>\n" 
                                   % ( URL,
                                       mxpassdate.year,
                                       passdate,
                                       DateTime(telem['time'].min()).date, 
                                       curr_color))
                    plot_pass( telem, pass_dir, redo=redo)
                    plt.figure(tfig['dacvsdtemp'].number)
                    # add randomization to dac
                    rand_dac = telem['dac'] + np.random.random(len(telem['dac']))-.5
                    plt.plot( telem['aca_temp']- telem['ccd_temp'], 
                          rand_dac,
                          color=curr_color, marker='.', markersize=.5)
                    for ttype in ('aca_temp', 'ccd_temp', 'dac'):
                        plt.figure(tfig[ttype].number)
                        plot_cxctime( [ DateTime(passdate).secs, DateTime(passdate).secs], 
                                      [ telem[ttype].mean(), telem[ttype].max() ],
                                      color=curr_color, linestyle='-', marker='^')
                        plot_cxctime( [ DateTime(passdate).secs, DateTime(passdate).secs], 
                                      [ telem[ttype].mean(), telem[ttype].min() ],
                                      color=curr_color, linestyle='-', marker='v')
                        plot_cxctime( [ DateTime(passdate).secs ], 
                                      [ telem[ttype].mean() ],
                                      color=curr_color, marker='.', markersize=10)

                except ValueError:
                    print "skipping %s" % pass_dir

            passlist.write("</TABLE>\n")
            passlist.close()

            h = plt.figure(tfig['dacvsdtemp'].number)
            plt.ylim(460,515)
            plt.xlim(37,40)
            plt.ylabel('TEC DAC Control Level')
            plt.xlabel('ACA temp - CCD temp (C)')
            h.subplots_adjust(bottom=0.2)
            plt.savefig(os.path.join(monthdir, 'dacvsdtemp.png'))
            plt.close(h)


            h = plt.figure(tfig['aca_temp'].number)
            plt.ylabel('ACA temp (C)')
            h.subplots_adjust(left=0.2)
            plt.ylim(17,22)
            plt.savefig(os.path.join(monthdir, 'aca_temp.png'))
            plt.close(h)

            h = plt.figure(tfig['ccd_temp'].number)
            plt.ylabel('CCD temp (C)')
            plt.ylim(-20,-18)
            h.subplots_adjust(left=0.2)
            plt.savefig(os.path.join(monthdir, 'ccd_temp.png'))
            plt.close(h)

            h = plt.figure(tfig['dac'].number)
            plt.ylim(460,515)
        #    xlim(cxctime2plotdate([DateTime(passdates[0]).secs - 86400,
        #                           DateTime(passdates[-1]).secs + 86400]))
            plt.ylabel('TEC DAC Control Level')
            plt.savefig(os.path.join(monthdir, 'dac.png'))
            plt.close(h)

            django_context = django.template.Context({ 'task' : { 'url' : URL },
                                                       'month' : { 'name' : month }})
            index = os.path.join(monthdir, 'index.html')
            log.info("making %s" % index)
        #    index_template_file = os.path.join(TASK_DATA, 'month_index_template.html')
            index_template_file = os.path.join(TASK_DATA, 'month_index_template.html')
            index_template = open(index_template_file).read()
            index_template = re.sub(r' %}\n', ' %}', index_template)
            template = django.template.Template(index_template)
            open(index, 'w').write(template.render(django_context))
    #        index = open(os.path.join(monthdir, 'index.html'), 'w')
    #        index.writelines(template)
    #        index.close()

    
    toptable.write("</TABLE>\n")
    toptable.close()

    topindex_template_file = os.path.join(TASK_DATA, 'top_index_template.html')
    topindex_template = open(topindex_template_file).read()
    topindex = open(os.path.join(TASK_DIR, 'index.html'), 'w')
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
    log.addHandler(ch)
    nowdate=DateTime(time.time(), format='unix').mxDateTime
    nowminus=nowdate - mx.DateTime.DateTimeDeltaFromDays(30)
    last_month_start = mx.DateTime.DateTime(nowminus.year, nowminus.month, 1)
    dirs = retrieve_perigee_telem(start=last_month_start)
    dirs.sort()
    for dir in dirs:
        per_pass_tasks( dir )
    month_stats_and_plots()


if __name__ == '__main__':
    main()
