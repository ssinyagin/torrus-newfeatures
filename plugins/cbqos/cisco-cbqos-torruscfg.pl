push( @Torrus::Collector::loadModules,
      'Torrus::Collector::Cisco_cbQoS' );

push( @Torrus::Validator::loadLeafValidators,
      'Torrus::Collector::Cisco_cbQoS_Params' );

1;
