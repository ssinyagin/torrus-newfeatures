# HTTP Collector Torrus plugin configuration

push( @Torrus::Collector::loadModules, 'Torrus::Collector::Http' );
push( @Torrus::Validator::loadLeafValidators, 'Torrus::Collector::Http' );

1;
