#
# Generate HTML files out of POD
#
# Stanislav Sinyagin <ssinyagin@yahoo.com>
#

gen_html () {
    in=$1
    opt=$2
    out=${HTMLDIR}/${in}.html
    css=torrusdoc.css
    
    if ( echo ${in} | grep '/' > /dev/null ); then
        css='../'${css}
    fi

    if test ! -f ${out} -o ${in} -nt ${out}; then
        echo Updating ${in}
        pod2html -css=${css} --infile=${in} --outfile=${out} ${opt}
    fi 
}

if test x${HTMLDIR} = x; then
    echo HTMLDIR environment variable not defined 1>&2
    exit 1
fi

for f in *.pod devdoc/*.pod; do
    gen_html $f
done
for f in manpages/*.pod; do
    gen_html $f --noindex
done

# Local Variables:
# mode: shell-script
# sh-shell: sh
# indent-tabs-mode: nil
# sh-basic-offset: 4
# End:
