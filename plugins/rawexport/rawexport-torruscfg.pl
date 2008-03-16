# HTTP Collector Torrus plugin configuration

push( @Torrus::Collector::loadModules, 'Torrus::Collector::RawExport' );
push( @Torrus::Validator::loadLeafValidators,
      'Torrus::Collector::RawExport_Params' );


# Limit of the export queue, in number of export files
$Torrus::Collector::RawExport::thrQueueLimit = 10000;



1;
