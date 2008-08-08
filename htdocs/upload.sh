
DEST="ssinyagin@shell.sourceforge.net:/home/groups/t/to/torrus/htdocs"

if test x"$*" = x; then
  scp -C *.html *.txt *.css $DEST
  scp -C manpages/*.html $DEST/manpages
  scp -C devdoc/*.html $DEST/devdoc
  scp -C plugins/*.html $DEST/plugins
  scp -C contrib/*.pl $DEST/contrib
  scp logo/*.png $DEST/logo
  scp torrus-functional-overview.* $DEST
else
  scp -C $* $DEST
fi
