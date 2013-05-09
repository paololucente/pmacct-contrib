pm_scripts = script-lib server-cfg top_talkers threshold_talkers delete_rows 
suffix = .pl

all: 
	 for f in $(pm_scripts) ; do \
	   perl_path=`which perl` ; \
	   /bin/rm -rf $$f$(suffix) ; \
	   sed \
	     -e "s!@PERL@!$$perl_path!" \
	     $$f > $@-t ; \
	   /bin/chmod +x $@-t ; \
	   /bin/mv $@-t $$f$(suffix) ; \
	 done

clean:
	 /bin/rm -rf *.pl

