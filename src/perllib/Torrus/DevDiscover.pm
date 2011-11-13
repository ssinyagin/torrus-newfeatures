#  Copyright (C) 2002-2011  Stanislav Sinyagin
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# Stanislav Sinyagin <ssinyagin@yahoo.com>

# Core SNMP device discovery module

package Torrus::DevDiscover;
use strict;
use warnings;

use POSIX qw(strftime);
use Net::SNMP qw(:snmp :asn1);
use Digest::MD5 qw(md5);

use Torrus::DevDiscover::DevDetails;
use Torrus::Log;

BEGIN
{
    foreach my $mod ( @Torrus::DevDiscover::loadModules )
    {
        if( not eval('require ' . $mod) or $@ )
        {
            die($@);
        }
    }
}

# Callback registry to inizialise multithreading before any threads are spawned
our %threading_init_callbacks;

# Callback registry to report discovery failures
our %discovery_failed_callbacks;

# Custom overlays for templates
# overlayName ->
#     'Module::templateName' -> { 'name' => 'templateName',
#                                 'source' => 'filename.xml' }
our %templateOverlays;

our @requiredParams =
    (
     'snmp-port',
     'snmp-version',
     'snmp-timeout',
     'snmp-retries',
     'data-dir',
     'snmp-host'
     );

our %defaultParams;

$defaultParams{'rrd-hwpredict'} = 'no';
$defaultParams{'domain-name'} = '';
$defaultParams{'host-subtree'} = '';
$defaultParams{'snmp-check-sysuptime'} = 'yes';
$defaultParams{'show-recursive'} = 'yes';
$defaultParams{'snmp-ipversion'} = '4';
$defaultParams{'snmp-transport'} = 'udp';

our @copyParams =
    ( 'collector-period',
      'collector-timeoffset',
      'collector-dispersed-timeoffset',
      'collector-timeoffset-min',
      'collector-timeoffset-max',
      'collector-timeoffset-step',
      'comment',
      'domain-name',
      'monitor-period',
      'monitor-timeoffset',
      'nodeid-device',
      'show-recursive',
      'snmp-host',
      'snmp-port',
      'snmp-localaddr',
      'snmp-localport',
      'snmp-ipversion',
      'snmp-transport',
      'snmp-community',
      'snmp-version',
      'snmp-username',
      'snmp-authkey',
      'snmp-authpassword',
      'snmp-authprotocol',
      'snmp-privkey',
      'snmp-privpassword',
      'snmp-privprotocol',
      'snmp-timeout',
      'snmp-retries',
      'snmp-oids-per-pdu',
      'snmp-check-sysuptime',
      'snmp-max-msg-size',
      'snmp-reachability-rra',
      'system-id' );


%Torrus::DevDiscover::oiddef =
    (
     'system'         => '1.3.6.1.2.1.1',
     'sysDescr'       => '1.3.6.1.2.1.1.1.0',
     'sysObjectID'    => '1.3.6.1.2.1.1.2.0',
     'sysUpTime'      => '1.3.6.1.2.1.1.3.0',
     'sysContact'     => '1.3.6.1.2.1.1.4.0',
     'sysName'        => '1.3.6.1.2.1.1.5.0',
     'sysLocation'    => '1.3.6.1.2.1.1.6.0'
     );

my @systemOIDs = ('sysDescr', 'sysObjectID', 'sysUpTime', 'sysContact',
                  'sysName', 'sysLocation');

sub new
{
    my $self = {};
    my $class = shift;
    my %options = @_;
    bless $self, $class;

    $self->{'oiddef'} = {};
    $self->{'oidrev'} = {};

    # Combine all %MODULE::oiddef hashes into one
    foreach my $module ( 'Torrus::DevDiscover',
                         @Torrus::DevDiscover::loadModules )
    {
        my $oiddef_ref = eval('\%'.$module.'::oiddef');
        die($@) if $@;
        if( ref($oiddef_ref) )
        {
            while( my($name, $oid) = each %{$oiddef_ref} )
            {
                $self->{'oiddef'}->{$name} = $oid;
                $self->{'oidrev'}->{$oid} = $name;
            }
        }
    }

    $self->{'datadirs'} = {};
    $self->{'globalData'} = {};

    return $self;
}



sub globalData
{
    my $self = shift;
    return $self->{'globalData'};
}


sub discover
{
    my $self = shift;
    my @paramhashes = @_;

    my $devdetails = new Torrus::DevDiscover::DevDetails();

    foreach my $params ( \%defaultParams, @paramhashes )
    {
        $devdetails->setParams( $params );
    }

    foreach my $param ( @requiredParams )
    {
        if( not defined( $devdetails->param( $param ) ) )
        {
            Error('Required parameter not defined: ' . $param);
            return 0;
        }
    }

    my %snmpargs;
    my $community;
    
    my $version = $devdetails->param( 'snmp-version' );
    $snmpargs{'-version'} = $version;    

    foreach my $arg ( qw(-port -localaddr -localport -timeout -retries) )
    {
        if( defined( $devdetails->param( 'snmp' . $arg ) ) )
        {
            $snmpargs{$arg} = $devdetails->param( 'snmp' . $arg );
        }
    }
    
    $snmpargs{'-domain'} = $devdetails->param('snmp-transport') . '/ipv' .
        $devdetails->param('snmp-ipversion');

    if( $version eq '1' or $version eq '2c' )
    {
        $community = $devdetails->param( 'snmp-community' );
        if( not defined( $community ) )
        {
            Error('Required parameter not defined: snmp-community');
            return 0;
        }
        $snmpargs{'-community'} = $community;

        # set maxMsgSize to a maximum value for better compatibility
        
        my $maxmsgsize = $devdetails->param('snmp-max-msg-size');
        if( defined( $maxmsgsize ) )
        {
            $devdetails->setParam('snmp-max-msg-size', $maxmsgsize);
            $snmpargs{'-maxmsgsize'} = $maxmsgsize;
        }        
    }
    elsif( $version eq '3' )        
    {
        foreach my $arg ( qw(-username -authkey -authpassword -authprotocol
                             -privkey -privpassword -privprotocol) )
        {
            if( defined $devdetails->param( 'snmp' . $arg ) )
            {
                $snmpargs{$arg} = $devdetails->param( 'snmp' . $arg );
            }
        }
        $community = $snmpargs{'-username'};
        if( not defined( $community ) )
        {
            Error('Required parameter not defined: snmp-user');
            return 0;
        }        
    }
    else
    {
        Error('Illegal value for snmp-version parameter: ' . $version);
        return 0;
    }

    my $hostname = $devdetails->param('snmp-host');
    my $domain = $devdetails->param('domain-name');

    if( $domain and index($hostname, '.') < 0 and index($hostname, ':') < 0 )
    {
         $hostname .= '.' . $domain;
    }
    $snmpargs{'-hostname'} = $hostname;

    my $port = $snmpargs{'-port'};

    my $time_start = time();
    Debug('Discovering host: ' . $hostname . ':' . $port . ':' . $community);

    my ($session, $error) =
        Net::SNMP->session( %snmpargs,
                            -nonblocking => 0,
                            -translate   => ['-all', 0, '-octetstring', 1] );
    if( not defined($session) )
    {
        Error('Cannot create SNMP session: ' . $error);
        return undef;
    }
    
    my @oids = ();
    foreach my $var ( @systemOIDs )
    {
        push( @oids, $self->oiddef( $var ) );
    }

    # This is the only checking if the remote agent is alive

    my $result = $session->get_request( -varbindlist => \@oids );
    if( defined $result )
    {
        $devdetails->storeSnmpVars( $result );
    }
    else
    {
        # When the remote agent is reacheable, but system objecs are
        # not implemented, we get a positive error_status
        if( $session->error_status() == 0 )
        {
            Error("Unable to communicate with SNMP agent on " . $hostname .
                  ':' . $port . ':' . $community . " - " . $session->error());
            return undef;
        }
    }

    my $data = $devdetails->data();
    $data->{'param'} = {};

    $data->{'templates'} = [];
    push( @{$data->{'templates'}},
          split( /\s*,\s*/,
                 $devdetails->paramString('custom-host-templates') ) );
    
    # Build host-level legend
    my %legendValues =
        (
         10 => {
             'name'  => 'Location',
             'value' => $devdetails->snmpVar($self->oiddef('sysLocation'))
             },
         20 => {
             'name'  => 'Contact',
             'value' => $devdetails->snmpVar($self->oiddef('sysContact'))
             },
         30 => {
             'name'  => 'System ID',
             'value' => $devdetails->param('system-id')
             },
         50 => {
             'name'  => 'Description',
             'value' => $devdetails->snmpVar($self->oiddef('sysDescr'))
             }
         );
     
    my $legend = '';
    foreach my $key ( sort keys %legendValues )
    {
        my $text = $legendValues{$key}{'value'};
        if( defined($text) and $text ne '' )
        {
            $text = $devdetails->screenSpecialChars( $text );
            $legend .= $legendValues{$key}{'name'} . ':' . $text . ';';
        }
    }
    
    if( $devdetails->paramEnabled('suppress-legend') )
    {
        $data->{'param'}{'legend'} = $legend;
    }

    # some parameters need just one-to-one copying

    my @hostCopyParams =
        split('\s*,\s*', $devdetails->paramString('host-copy-params'));
    
    foreach my $param ( @copyParams, @hostCopyParams )
    {
        my $val = $devdetails->param( $param );
        if( defined($val) )
        {
            $data->{'param'}{$param} = $val;
        }
    }

    # If snmp-host is ipv6 address, system-id needs to be adapted to
    # remove colons
    
    if( not defined( $data->{'param'}{'system-id'} ) and
        index($data->{'param'}{'snmp-host'}, ':') >= 0 )
    {
        my $systemid = $data->{'param'}{'snmp-host'};
        $systemid =~ s/:/_/g;
        $data->{'param'}{'system-id'} = $systemid;
    }

    if( not defined( $devdetails->snmpVar($self->oiddef('sysUpTime')) ) )
    {
        Debug('Agent does not support sysUpTime');
        $data->{'param'}{'snmp-check-sysuptime'} = 'no';
    }

    $data->{'param'}{'data-dir'} =
        $self->genDataDir( $devdetails->param('data-dir'), $hostname );

    # Register the directory for listDataDirs()
    $self->{'datadirs'}{$devdetails->param('data-dir')} = 1;

    $self->{'session'} = $session;

    # some discovery modules need to be disabled on per-device basis

    my %onlyDevtypes;
    my $useOnlyDevtypes = 0;
    foreach my $devtype ( split('\s*,\s*',
                                $devdetails->paramString('only-devtypes') ) )
    {
        $onlyDevtypes{$devtype} = 1;
        $useOnlyDevtypes = 1;
    }

    my %disabledDevtypes;
    foreach my $devtype ( split('\s*,\s*',
                                $devdetails->paramString('disable-devtypes') ) )
    {
        $disabledDevtypes{$devtype} = 1;
    }

    # 'checkdevtype' procedures for each known device type return true
    # when it's their device. They also research the device capabilities.
    my $reg = \%Torrus::DevDiscover::registry;
    foreach my $devtype
        ( sort {$reg->{$a}{'sequence'} <=> $reg->{$b}{'sequence'}}
          keys %{$reg} )
    {
        if( ( not $useOnlyDevtypes or $onlyDevtypes{$devtype} ) and
            not $disabledDevtypes{$devtype} and
            &{$reg->{$devtype}{'checkdevtype'}}($self, $devdetails) )
        {
            $devdetails->setDevType( $devtype );
            Debug('Found device type: ' . $devtype);
        }
    }

    my @devtypes = sort {
        $reg->{$a}{'sequence'} <=> $reg->{$b}{'sequence'}
    } $devdetails->getDevTypes();
    $data->{'param'}{'devdiscover-devtypes'} = join(',', @devtypes);

    $data->{'param'}{'devdiscover-nodetype'} = '::device';

    # Do the detailed discovery and prepare data
    my $ok = 1;
    foreach my $devtype ( @devtypes )
    {
        $ok = &{$reg->{$devtype}{'discover'}}($self, $devdetails) ? $ok:0;
    }

    delete $self->{'session'};
    $session->close();

    $devdetails->applySelectors();
        
    my $subtree = $devdetails->param('host-subtree');
    if( not defined( $self->{'devdetails'}{$subtree} ) )
    {
        $self->{'devdetails'}{$subtree} = [];
    }
    push( @{$self->{'devdetails'}{$subtree}}, $devdetails );

    foreach my $pair
        ( split(/\s*;\s*/, $devdetails->paramString('define-tokensets') ) )
    {
        my( $tset, $description ) = split( /\s*:\s*/, $pair );
        my $params = {};
        
        if( $tset !~ /^[a-z][a-z0-9-_]*$/ )
        {
            Error('Invalid name for tokenset: ' . $tset);
            $ok = 0;
        }
        elsif( not defined($description) or $description eq '' )
        {
            Error('Missing description for tokenset: ' . $tset);
            $ok = 0;
        }
        else
        {
            $params->{'comment'} = $description;
        }
        
        my $v = $devdetails->param($tset . '-tokenset-rrgraph-view');
        if( defined($v) )
        {
            $params->{'rrgraph-view'} = $v;
        }
        
        if( $ok )
        {
            $self->{'define-tokensets'}{$tset} = $params;
        }
    }

    Verbose('Discovery for ' . $hostname . ' finished in ' .
            (time() - $time_start) . ' seconds');
    
    return $ok;
}


sub buildConfig
{
    my $self = shift;
    my $cb = shift;

    my $reg = \%Torrus::DevDiscover::registry;
        
    foreach my $subtree ( sort keys %{$self->{'devdetails'}} )
    {
        # Chop the first and last slashes
        my $path = $subtree;
        $path =~ s/^\///;
        $path =~ s/\/$//;

        # generate subtree path XML
        my $subtreeNode = undef;
        foreach my $subtreeName ( split( '/', $path ) )
        {
            $subtreeNode = $cb->addSubtree( $subtreeNode, $subtreeName );
        }

        foreach my $devdetails
            ( sort {$a->param('snmp-host') cmp $b->param('snmp-host')}
              @{$self->{'devdetails'}{$subtree}} )
        {

            my $data = $devdetails->data();

            my @registryOverlays = ();
            if( defined( $devdetails->param('template-registry-overlays' ) ) )
            {
                my @overlayNames = 
                    split(/\s*,\s*/,
                          $devdetails->param('template-registry-overlays' ));
                foreach my $overlayName ( @overlayNames )
                {
                    if( defined( $templateOverlays{$overlayName}) )
                    {
                        push( @registryOverlays,
                              $templateOverlays{$overlayName} );
                    }
                    else
                    {
                        Error('Cannot find the template overlay named ' .
                              $overlayName);
                    }
                }
            }

            # we should call this anyway, in order to flush the overlays
            # set by previous host
            $cb->setRegistryOverlays( @registryOverlays );            
            
            if( $devdetails->paramEnabled('disable-snmpcollector' ) )
            {
                push( @{$data->{'templates'}}, '::viewonly-defaults' );
            }
            else
            {
                push( @{$data->{'templates'}}, '::snmp-defaults' );
            }

            if( $devdetails->paramEnabled('rrd-hwpredict' ) )
            {
                push( @{$data->{'templates'}}, '::holt-winters-defaults' );
            }
            
            if( $devdetails->paramDisabled('disable-reachability-stats') 
                and
                (
                 (not defined($devdetails->param('only-devtypes')))
                 or
                 $devdetails->paramEnabled('enable-reachability-stats') 
                ) )
            {
                push( @{$data->{'templates'}}, '::snmp-reachability' );
            }

            
            my $devNodeName = $devdetails->paramString('symbolic-name');
            if( $devNodeName eq '' )
            {
                $devNodeName = $devdetails->paramString('system-id');
                if( $devNodeName eq '' )
                {
                    $devNodeName = $devdetails->param('snmp-host');
                }
            }                
                
            my $devNode = $cb->addSubtree( $subtreeNode, $devNodeName,
                                           $data->{'param'},
                                           $data->{'templates'} );

            foreach my $alias
                ( split( '\s*,\s*',
                         $devdetails->paramString('host-aliases') ) )
            {
                $cb->addAlias( $devNode, $alias );
            }

            foreach my $file
                ( split( '\s*,\s*',
                         $devdetails->paramString('include-files') ) )
            {
                $cb->addFileInclusion( $file );
            }
                    

            # Let the device type-specific modules add children
            # to the subtree
            foreach my $devtype
                ( sort {$reg->{$a}{'sequence'} <=> $reg->{$b}{'sequence'}}
                  $devdetails->getDevTypes() )
            {
                &{$reg->{$devtype}{'buildConfig'}}
                ( $devdetails, $cb, $devNode, $self->{'globalData'} );
            }

            $cb->{'statistics'}{'hosts'}++;
        }
    }

    foreach my $devtype
        ( sort {$reg->{$a}{'sequence'} <=> $reg->{$b}{'sequence'}}
          keys %{$reg} )
    {
        if( defined( $reg->{$devtype}{'buildGlobalConfig'} ) )
        {
            &{$reg->{$devtype}{'buildGlobalConfig'}}($cb,
                                                     $self->{'globalData'});
        }
    }
    
    if( defined( $self->{'define-tokensets'} ) )
    {
        my $tsetsNode = $cb->startTokensets();
        foreach my $tset ( sort keys %{$self->{'define-tokensets'}} )
        {
            $cb->addTokenset( $tsetsNode, $tset, 
                              $self->{'define-tokensets'}{$tset} );
        }
    }
    return;
}



sub session
{
    my $self = shift;
    return $self->{'session'};
}

sub oiddef
{
    my $self = shift;
    my $var = shift;

    my $ret = $self->{'oiddef'}->{$var};
    if( not $ret )
    {
        Error('Undefined OID definition: ' . $var);
    }
    return $ret;
}


sub oidref
{
    my $self = shift;
    my $oid = shift;
    return $self->{'oidref'}->{$oid};
}


sub genDataDir
{
    my $self = shift;
    my $basedir = shift;
    my $hostname = shift;

    if( $Torrus::DevDiscover::hashDataDirEnabled )
    {
        return $basedir . '/' .
            sprintf( $Torrus::DevDiscover::hashDataDirFormat,
                     unpack('N', md5($hostname)) %
                     $Torrus::DevDiscover::hashDataDirBucketSize );
    }
    else
    {
        return $basedir;
    }
}


sub listDataDirs
{
    my $self = shift;

    my @basedirs = keys %{$self->{'datadirs'}};
    my @ret = @basedirs;

    if( $Torrus::DevDiscover::hashDataDirEnabled )
    {
        foreach my $basedir ( @basedirs )
        {
            for( my $i = 0;
                 $i < $Torrus::DevDiscover::hashDataDirBucketSize;
                 $i++ )
            {
                push( @ret, $basedir . '/' .
                      sprintf( $Torrus::DevDiscover::hashDataDirFormat, $i ) );
            }
        }
    }
    return @ret;
}

##
# Check if SNMP table is present, without retrieving the whole table

sub checkSnmpTable
{
    my $self = shift;
    my $oidname = shift;

    my $session = $self->session();
    my $oid = $self->oiddef( $oidname );

    my $result = $session->get_next_request( -varbindlist => [ $oid ] );
    if( defined( $result ) )
    {
        # check if the returned oid shares the base of the query
        my $firstOid = (keys %{$result})[0];
        if( Net::SNMP::oid_base_match( $oid, $firstOid ) and
            $result->{$firstOid} ne '' )
        {
            return 1;
        }
    }
    return 0;
}


##
# Check if given OID is present

sub checkSnmpOID
{
    my $self = shift;
    my $oidname = shift;

    my $session = $self->session();
    my $oid = $self->oiddef( $oidname );

    my $result = $session->get_request( -varbindlist => [ $oid ] );
    if( $session->error_status() == 0 and
        defined($result) and
        defined($result->{$oid}) and
        $result->{$oid} ne '' )
    {
        return 1;
    }
    return 0;
}


##
# retrieve the given OIDs by names and return hash with values

sub retrieveSnmpOIDs
{
    my $self = shift;
    my @oidnames = @_;

    my $session = $self->session();
    my $oids = [];
    foreach my $oidname ( @oidnames )
    {
        push( @{$oids}, $self->oiddef( $oidname ) );
    }                   

    my $result = $session->get_request( -varbindlist => $oids );
    if( $session->error_status() == 0 and defined( $result ) )
    {
        my $ret = {};
        foreach my $oidname ( @oidnames )
        {
            $ret->{$oidname} = $result->{$self->oiddef( $oidname )};
        }
        return $ret;
    }
    return undef;
}

##
# Simple wrapper for Net::SNMP::oid_base_match

sub oidBaseMatch
{
    my $self = shift;
    my $base_oid = shift;
    my $oid = shift;

    if( $base_oid =~ /^\D/ )
    {
        $base_oid = $self->oiddef( $base_oid );
    }
    return Net::SNMP::oid_base_match( $base_oid, $oid );
}

##
# some discovery modules need to adjust max-msg-size

sub setMaxMsgSize
{
    my $self = shift;
    my $devdetails = shift;
    my $msgsize = shift;
    my $opt = shift;

    $opt = {} unless defined($opt);

    if( (not $opt->{'only_v1_and_v2'}) or $self->session()->version() != 3 )
    {
        $self->session()->max_msg_size($msgsize);
        $devdetails->data()->{'param'}{'snmp-max-msg-size'} = $msgsize;
    }
    return;
}

    


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
