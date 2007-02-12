
TASK = perigee_health_plots

include /proj/sot/ska/include/Makefile.FLIGHT

SHARE = pass_plots.pl aca_health.pro index.html startup.pro install_plots.pl
DATA = pass_plots.cfg

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
ifdef SHARE
	mkdir -p $(INSTALL_SHARE)
	rsync --times --cvs-exclude $(SHARE) $(INSTALL_SHARE)/
endif
