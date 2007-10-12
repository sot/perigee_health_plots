
TASK = perigee_health_plots
VERSION = 1.1

include /proj/sot/ska/include/Makefile.FLIGHT

SHARE = shared.yaml get_perigee_telem.pl get_perigee_telem.yaml perigee_telem_parse.pl perigee_telem_parse.yaml pass_stats_and_plots.pl plot_summary.yaml plot_health.yaml install_plots.pl install_plots.yaml make_month_summary.pl make_month_summary.yaml check_telem.pl check_telem.yaml data_file_comments.txt report_template.txt
DATA = pass_plots.cfg column_conversion.yaml aca8x8.fits.gz 
LIB = Telemetry.pm 
PERIGEELIB = Data.pm DataObject.pm  Pass.pm Range.pm


radmon:
	mkdir -p $(INSTALL)/data/arc/iFOT_events/radmon/
	rsync --times --cvs-exclude /proj/sot/ska/data/arc/iFOT_events/radmon/*.rdb $(INSTALL)/data/arc/iFOT_events/radmon/

test: check_install radmon install
	$(INSTALL_SHARE)/pass_plots.pl 
	$(INSTALL_SHARE)/install_plots.pl -web_dir "./web/"

install: 
ifdef DATA
	mkdir -p $(INSTALL_DATA)
	rsync --times --cvs-exclude $(DATA) $(INSTALL_DATA)/
endif
ifdef SHARE
	mkdir -p $(INSTALL_SHARE)
	rsync --times --cvs-exclude $(SHARE) $(INSTALL_SHARE)/
endif
ifdef LIB
	mkdir -p $(INSTALL_PERLLIB)/Ska/
	rsync --times --cvs-exclude $(LIB) $(INSTALL_PERLLIB)/Ska/
endif
ifdef PERIGEELIB
	mkdir -p $(INSTALL_PERLLIB)/Ska/Perigee/
	rsync --times --cvs-exclude $(PERIGEELIB) $(INSTALL_PERLLIB)/Ska/Perigee/
endif


dist:
	mkdir $(TASK)-$(VERSION)
	rsync -aruvz --cvs-exclude --exclude $(TASK)-$(VERSION) * $(TASK)-$(VERSION)
	tar cvf $(TASK)-$(VERSION).tar $(TASK)-$(VERSION)
	gzip --best $(TASK)-$(VERSION).tar
	rm -rf $(TASK)-$(VERSION)/
