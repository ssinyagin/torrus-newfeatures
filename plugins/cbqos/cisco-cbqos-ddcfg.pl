push( @Torrus::DevDiscover::loadModules,
      'Torrus::DevDiscover::CiscoIOS_cbQoS' );

# List of default DSCP values to be monitored for RED statistics.
# May be redefined in devdiscover-siteconfig.pl, or in DDX parameter:
# <param name="CiscoIOS_cbQoS::red-dscp-values" value="0,AF21,AF22,AF23,EF"/>

@Torrus::DevDiscover::CiscoIOS_cbQoS::RedDscpValues =
    qw(0 AF21 AF22 AF31 AF32 AF41 AF42 EF);


$Torrus::ConfigBuilder::templateRegistry{
    'CiscoIOS_cbQoS::cisco-cbqos-subtree'} = {
        'name'   => 'cisco-cbqos-subtree',
        'source' => 'vendor/cisco.ios.cbqos.xml'
        };

$Torrus::ConfigBuilder::templateRegistry{
    'CiscoIOS_cbQoS::cisco-cbqos-policymap-subtree'} = {
        'name'   => 'cisco-cbqos-policymap-subtree',
        'source' => 'vendor/cisco.ios.cbqos.xml'
        };
    
$Torrus::ConfigBuilder::templateRegistry{
    'CiscoIOS_cbQoS::cisco-cbqos-classmap-meters'} = {
        'name'   => 'cisco-cbqos-classmap-meters',
        'source' => 'vendor/cisco.ios.cbqos.xml'
        };

$Torrus::ConfigBuilder::templateRegistry{
    'CiscoIOS_cbQoS::cisco-cbqos-match-stmt-meters'} = {
        'name'   => 'cisco-cbqos-match-stmt-meters',
        'source' => 'vendor/cisco.ios.cbqos.xml'
        };

$Torrus::ConfigBuilder::templateRegistry{
    'CiscoIOS_cbQoS::cisco-cbqos-police-meters'} = {
        'name'   => 'cisco-cbqos-police-meters',
        'source' => 'vendor/cisco.ios.cbqos.xml'
        };

$Torrus::ConfigBuilder::templateRegistry{
    'CiscoIOS_cbQoS::cisco-cbqos-queueing-meters'} = {
        'name'   => 'cisco-cbqos-queueing-meters',
        'source' => 'vendor/cisco.ios.cbqos.xml'
        };

$Torrus::ConfigBuilder::templateRegistry{
    'CiscoIOS_cbQoS::cisco-cbqos-shaping-meters'} = {
        'name'   => 'cisco-cbqos-shaping-meters',
        'source' => 'vendor/cisco.ios.cbqos.xml'
        };

$Torrus::ConfigBuilder::templateRegistry{
    'CiscoIOS_cbQoS::cisco-cbqos-red-subtree'} = {
        'name'   => 'cisco-cbqos-red-subtree',
        'source' => 'vendor/cisco.ios.cbqos.xml'
        };

$Torrus::ConfigBuilder::templateRegistry{
    'CiscoIOS_cbQoS::cisco-cbqos-red-meters'} = {
        'name'   => 'cisco-cbqos-red-meters',
        'source' => 'vendor/cisco.ios.cbqos.xml'
        };

1;
