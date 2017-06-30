for m in \
    Redis::Fast \
    Git::Raw \
    Git::ObjectStore \
    Digest::SHA \
    Cache::Ref \
    JSON \
    JSON::XS \
    XML::LibXML \
    Template \
    Proc::Daemon \
    Net::SNMP \
    URI::Escape \
    Apache::Session \
    Date::Parse \
    CGI::Fast \
    FCGI \
;do
    cpanm --notest $m
    if [ $? -ne 0 ]; then exit 1; fi
done

