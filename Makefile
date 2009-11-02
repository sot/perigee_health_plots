
TASK = perigee_health_plots
VERSION = 2.0

include /proj/sot/ska/include/Makefile.FLIGHT

SHARE = get_perigee_telem.pl pass_plots.py month_index_template.html pass_index_template.html top_index_template.html


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


dist:
	mkdir $(TASK)-$(VERSION)
	rsync -aruvz --cvs-exclude --exclude $(TASK)-$(VERSION) * $(TASK)-$(VERSION)
	tar cvf $(TASK)-$(VERSION).tar $(TASK)-$(VERSION)
	gzip --best $(TASK)-$(VERSION).tar
	rm -rf $(TASK)-$(VERSION)/
