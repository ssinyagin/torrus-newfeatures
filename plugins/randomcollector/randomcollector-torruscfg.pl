# HTTP Collector Torrus plugin configuration

push( @Torrus::Collector::loadModules, 'Torrus::Collector::Random' );
push( @Torrus::Validator::loadLeafValidators, 'Torrus::Collector::Random' );

1;
