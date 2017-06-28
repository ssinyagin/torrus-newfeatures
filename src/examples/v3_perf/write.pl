use strict;
use warnings;
use Digest::SHA qw(sha1_hex);
use File::Path qw(make_path);
use JSON;
use IO::File;


my $homedir = '/opt/t3/t/data/';
my $count = $ARGV[0] or die("Need numeric argument");

my $data = {
    'docsIfDownstreamChannelTable' => '1.3.6.1.2.1.10.127.1.1.1',
    'docsIfCmtsDownChannelCounterTable' => '1.3.6.1.2.1.10.127.1.3.10',
    'docsIfSigQSignalNoise' => '1.3.6.1.2.1.10.127.1.1.4.1.5',
    'ciscoLS1010'                       => '1.3.6.1.4.1.9.1.107',
    'ciscoImageTable'                   => '1.3.6.1.4.1.9.9.25.1.1',
    'ceImageTable'                      => '1.3.6.1.4.1.9.9.249.1.1.1',
    'bufferElFree'                      => '1.3.6.1.4.1.9.2.1.9.0',
    'cipSecGlobalHcInOctets'            => '1.3.6.1.4.1.9.9.171.1.3.1.4.0',
    'cbgpPeerAddrFamilyName'            => '1.3.6.1.4.1.9.9.187.1.2.3.1.3',
    'cbgpPeerAcceptedPrefixes'          => '1.3.6.1.4.1.9.9.187.1.2.4.1.1',
    'cbgpPeerPrefixAdminLimit'          => '1.3.6.1.4.1.9.9.187.1.2.4.1.3',
    'ccarConfigType'                    => '1.3.6.1.4.1.9.9.113.1.1.1.1.3',
    'ccarConfigAccIdx'                  => '1.3.6.1.4.1.9.9.113.1.1.1.1.4',
    'ccarConfigRate'                    => '1.3.6.1.4.1.9.9.113.1.1.1.1.5',
    'ccarConfigLimit'                   => '1.3.6.1.4.1.9.9.113.1.1.1.1.6',
    'ccarConfigExtLimit'                => '1.3.6.1.4.1.9.9.113.1.1.1.1.7',
    'ccarConfigConformAction'           => '1.3.6.1.4.1.9.9.113.1.1.1.1.8',
    'ccarConfigExceedAction'            => '1.3.6.1.4.1.9.9.113.1.1.1.1.9',
    'cvpdnSystemTunnelTotal'            => '1.3.6.1.4.1.9.10.24.1.1.4.1.2',
    'c3gStandard'                       => '1.3.6.1.4.1.9.9.661.1.1.1.1',
    'cportQosDropPkts'                  => '1.3.6.1.4.1.9.9.189.1.3.2.1.7',
};

my $json = JSON->new;

while( $count-- > 0 )
{
    my $sha = sha1_hex(' ' . $count . ' ');

    my $dir = $homedir . substr($sha, 0, 2) . '/' .
        substr($sha, 2, 2) . '/';

    if( not -d $dir )
    {
        make_path($dir) or die("Cannot mkdir $dir: $!");
    }
    
    my $filepath = $dir . $sha;
       
    my $fh = IO::File->new($filepath, 'w') or die("Cannot open $filepath: $!");
    $fh->print($json->encode($data));
    $fh->close;
}

