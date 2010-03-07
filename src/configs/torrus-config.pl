#  Copyright (C) 2002  Stanislav Sinyagin
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

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>


# DO NOT EDIT THIS FILE!

# Torrus local configuration.
# Put all your local settings into torrus-siteconfig.pl

use lib(@perllibdirs@);

$Torrus::Global::version        = '@VERSION@';
$Torrus::Global::cfgDefsDir     = '@cfgdefdir@';
$Torrus::Global::cfgSiteDir     = '@siteconfdir@';
$Torrus::Global::pkgbindir      = '@pkgbindir@';
$Torrus::Global::dbHome         = '@dbhome@';
$Torrus::Global::templateDirs   = ['@tmpldir@', '@tmpluserdir@'];
$Torrus::Global::stylingDir     = '@styldir@';
$Torrus::Global::cacheDir       = '@cachedir@';
$Torrus::Global::pidDir         = '@piddir@';
$Torrus::Global::logDir         = '@logdir@';
$Torrus::Global::reportsDir     = '@reportsdir@';
$Torrus::Global::sesStoreDir    = '@sesstordir@';
$Torrus::Global::sesLockDir     = '@seslockdir@';
$Torrus::Global::webPlainDir    = '@webplaindir@';

@Torrus::Global::xmlDirs        = ('@distxmldir@', '@sitexmldir@');

$Torrus::Global::threadsEnabled  = '@perlithreads@';

$Torrus::DB::dbSub              = 'sub';

# How long we can wait till the configuration is ready, in seconds
$Torrus::Global::ConfigReadyTimeout = 1800;

# How often we check if the configuration is ready, in seconds
$Torrus::Global::ConfigReadyRetryPeriod = 30;

# How long the compiler waits till readers finish, in seconds
$Torrus::Global::ConfigReadersWaitTimeout = 180;

# How often compiler checks for readers to finish
$Torrus::Global::ConfigReadersWaitPeriod = 5;

# How much the timestamps can differ in one RRD file, in seconds
$Torrus::Global::RRDTimestampTolerance = 15;

# SO_RCVBUF, the receiving buffer size of the SNMP collector socket.
# Should be large enough to sustain the traffic bursts, and should be
# within limits incurred by local OS and kernel settings.
# Check your system manuals and the results of network statistics.
#
# On Solaris, the maximum buffer size is 256k, and it is configurable
# via "/usr/sbin/ndd /dev/udp udp_max_buf <value>",
# and the statistics are shown in udpInOverflows of "netstat -s -P ip" output.
#
# On FreeBSD, the statistics can be obtained via "netstat -s -p udp".
# The maximum socket buffer can be changed via
# "sysctl kern.ipc.maxsockbuf=<value>", and default is 256k.
# On startup, the OS reads these settings from /etc/sysctl.conf
#
# On Linux (FC2), the default limit is 131071, and it can be changed
# by "sysctl -w net.core.rmem_max=<value>". On startup, the OS reads these
# settings from /etc/sysctl.conf
#
$Torrus::Collector::SNMP::RxBuffer = 131071;

# The time period after which we give up to reach the host being unreachable
$Torrus::Collector::SNMP::unreachableTimeout = 21600; # 6 hours

# For unreachable host, we retry SNMP query not earlier than this
$Torrus::Collector::SNMP::unreachableRetryDelay = 600; # 10 min

# Variables that define the SNMP map refreshing.
# The maps (e.g. ifDescr=>ifIndex mapping) are stored in the collector
# process and are not automatically refreshed after recompiling.
# They refresh only when the SNMP agent is rebooted or at periodic intervals
# defined below. For SNMPv1 agents, periodic refreshing is disabled
# because of performance impact.
#
# Refresh SNMP maps every 5 to 7 hours
$Torrus::Collector::SNMP::mapsRefreshPeriod = 18000;
$Torrus::Collector::SNMP::mapsRefreshRandom = 0.40;

# Wait 10min between refresh checkups
$Torrus::Collector::SNMP::mapsExpireCheckPeriod = 600;

# There is a strange bug that with more than 400 sessions per SNMP
# dispatcher some requests are not sent at all
$Torrus::Collector::SNMP::maxSessionsPerDispatcher = 100;

# When enabled, the collector starts a background thread that
# writes to RRD files
$Torrus::Collector::RRDStorage::useThreads = $Torrus::Global::threadsEnabled;

# How many unwritten updates are allowed to stay in the queue
$Torrus::Collector::RRDStorage::thrQueueLimit = 1000000;

# The following errors are caused by changes in the device configurations,
# when the collector tries to store data in a RRD file, but the
# structure of the file is no longer suitable:
#     Datasource exists in RRD file, but is not updated
#     Datasource being updated does not exist
# Set this variable to true if you want these RRD files automatically moved.
# The current date is appended to the filename, and the file
# is moved to another directory or renamed.
$Torrus::Collector::RRDStorage::moveConflictRRD = 0;


# The path where conflicted RRD files would be moved. This directory
# should exist, be writable by Torrus daemon user, and in most OSes
# it must reside in the same filesystem as the original files.
# When undefined, the files are renamed within their original directory.
$Torrus::Collector::RRDStorage::conflictRRDPath = undef;

# Sleep interval when scheduler initialization failed (i.e. configuration
# reading timeout)
$Torrus::Scheduler::failedInitSleep = 1800;

# When positive, the scheduler will sleep in small intervals.
# Use this when the system clock is not reliable, like in VmWare
$Torrus::Scheduler::maxSleepTime = 0;

# Set this to true when the system clock is not reliable, like in VmWare
$Torrus::Scheduler::ignoreClockSkew = 0;

# Exponential decay parameter (alpha) for Scheduler statistics averages:
#
# Xnew = alpha * Xmes + (1-alpha) * Xprev
# Xnew: new calculated average
# Xmes: measured value
# Xprev: old calculated average
#
# Alpha defines how many previous measurements composite the average:
# alpha = 1.0 - exp( log(1-TotalWeight)/NPoints )
# TotalWeight: the weight of NPoints measurements
# NPoints: number of measurements
# 0.63 corresponds to TotalWeight=0.95 and NPoints=3 (95% of average is from
# last three datapoints
#
$Torrus::Scheduler::statsExpDecayAlpha = 0.63;

# Monitor alarms may become orphaned if the configuration changes
# in the middle of an event. Events older than this time are cleaned up
# default: 2 weeks
$Torrus::Monitor::alarmTimeout = 1209600; 

# The default CSS stylesheet and other details for HTML output.
# These settings may optionally be overwritten by the styling profile below.
# Additional CSS overlay may be specified with 'cssoverlay' property,
# for example:
# $Torrus::Renderer::styling{'default'}{'cssoverlay'} = 'mystyle.css';
#
%Torrus::Renderer::styling =
    ( 'default' => {'stylesheet'   => 'torrus.css'},
      'printer' => {'stylesheet'   => 'torrus-printer.css'},
      'report'  => {'stylesheet'   => 'torrus-report.css'}
      );

# Color schema for RRDtool graph. It can be extended by setting
# $Torrus::Renderer::stylingProfileOverlay. The overlay should
# be an absolute file name. You can use $Torrus::Global::cfgSiteDir
# to refer to the site configs path.
$Torrus::Renderer::stylingProfile = 'torrus-schema';

# Top level URI
$Torrus::Renderer::rendererURL = '/torrus';

# Trailing slash is important!
$Torrus::Renderer::plainURL = '/torrus/plain/';

# The small piece of text in the corner of the HTML output.
$Torrus::Renderer::companyName = 'Your company name';

# The URL to use for that piece of text
$Torrus::Renderer::companyURL = 'http://torrus.sf.net';

# The URL of your company logo which will be displayed instead of
# companyName
# $Torrus::Renderer::companyLogo = 'http://domain.com/logo.png';

# Another piece of text on the right to the company name
$Torrus::Renderer::siteInfo = undef;

# URL to be shown on the login page for lost password
# You have to implement that yourself
# $Torrus::Renderer::lostPasswordURL = 'http://domain.com/lostpw.cgi';
    
# The time format to print in HTML
$Torrus::Renderer::timeFormat = '%d-%m-%Y %H:%M';

# The page that lets you choose the tree from the list
$Torrus::Renderer::Chooser::mimeType = 'text/html; charset=UTF-8';
$Torrus::Renderer::Chooser::expires = '300';
$Torrus::Renderer::Chooser::template = 'default-chooser.html';
$Torrus::Renderer::Chooser::searchTemplate = 'globalsearch.html';

# We clean the renderer cache at least once a day
$Torrus::Renderer::cacheMaxAge = 86400;

# Some RRDtool versions may report errors on decorations
$Torrus::Renderer::ignoreDecorations = 0;

# This enables full Apache handler debugging
$Torrus::Renderer::globalDebug = 0;

# When true, Holt-Winters boundaries and failures are described in the
# graph legend
$Torrus::Renderer::hwGraphLegend = 0;

# When true, users may view service usage reports (requires SQL connection)
$Torrus::Renderer::displayReports = 0;

# Allow tree searching. The search DB should be built with buildsearchdb
$Torrus::Renderer::searchEnabled = 1;

# Allow global searching across the trees. If the user authentication
# is enabled, the user should have rights DisplayTree and GlobalSearch for '*'
$Torrus::Renderer::globalSearchEnabled = 1;


# Modules that Collector will use for collecting and storing data.
@Torrus::Collector::loadModules =
    ( 'Torrus::Collector::SNMP',
      'Torrus::Collector::CDef',
      'Torrus::Collector::RRDStorage' );

# Configurable part of Validator
@Torrus::Validator::loadLeafValidators =
    ( 'Torrus::Collector::SNMP_Params',
      'Torrus::Collector::CDef_Params' );

# Configurable part of AdmInfo renderer
@Torrus::Renderer::loadAdmInfo =
    ( 'Torrus::Collector::SNMP_Params',
      'Torrus::Collector::CDef_Params' );

# Parameters that are comma-separated values
@Torrus::ConfigTree::XMLCompiler::listparams = ();

# XML files to be compiled first for every tree
@Torrus::Global::xmlAlwaysIncludeFirst = ();

# XML files to be compiled after the tree files, but before the files
# included with <include> XML directive
@Torrus::Global::xmlAlwaysIncludeLast = ();

# Do we need Web user authentication/authorization ?
$Torrus::ApacheHandler::authorizeUsers = 1;

# User authentication method may be changed locally
$Torrus::ACL::userAuthModule = 'Torrus::ACL::AuthLocalMD5';

# Minimum allowed password length
$Torrus::ACL::minPasswordLength = 6;

# The login page
$Torrus::Renderer::LoginScreen::mimeType = 'text/html; charset=UTF-8';
$Torrus::Renderer::LoginScreen::template = 'default-login.html';

####
####  SQL connections configuration
# For a given Perl class and an optional subtype,
# the connection attributes are derived in the following order:
# 'Default', 'Default/[subtype]', '[Class]', '[Class]/[subtype]',
# 'All/[subtype]'.
# For a simple setup, the default attributes are usually defined for
# 'Default' key.
# The key attributes are: 'dsn', 'username', and 'password'.
%Torrus::SQL::connections =
    ('Default' => {'dsn' => 'DBI:mysql:database=torrus;host=localhost',
                   'username' => 'torrus',
                   'password' => 'torrus'}
     );

####
####  ExternalStorage collector module initialization.
# In order to enable External storage, add these lines to torrus-siteconfig.pl:
# push(@Torrus::Collector::loadModules, 'Torrus::Collector::ExternalStorage');
# 

# Other configuration available:

# Maximum age for backlog in case of unavailable storage.
# We stop recording new data when maxage is reached. Default: 24h
$Torrus::Collector::ExternalStorage::backlogMaxAge = 86400;

# How often we retry to contact an unreachable external storage. Default: 10min
$Torrus::Collector::ExternalStorage::unavailableRetry = 600;

# Backend engine for External storage
$Torrus::Collector::ExternalStorage::backend = 'Torrus::Collector::ExtDBI';

# SQL table configuration for collector's external storage
$Torrus::SQL::SrvExport::tableName = 'srvexport';
%Torrus::SQL::SrvExport::columns =
    ('srv_date'    => 'srv_date',
     'srv_time'    => 'srv_time',
     'serviceid'   => 'serviceid',
     'value'       => 'value',
     'intvl'       => 'intvl');

# Optional SQL connection subtype for Collector export
# $Torrus::Collector::ExtDBI::subtype


# SQL table configuration for Reports
$Torrus::SQL::Reports::tableName = 'reports';
%Torrus::SQL::Reports::columns =
    ('id'          => 'id',
     'rep_date'    => 'rep_date',
     'rep_time'    => 'rep_time',
     'reportname'  => 'reportname',
     'iscomplete'  => 'iscomplete');

$Torrus::SQL::ReportFields::tableName = 'reportfields';
%Torrus::SQL::ReportFields::columns =
    ('id'         => 'id',
     'rep_id'     => 'rep_id',
     'name'       => 'name',
     'serviceid'  => 'serviceid',
     'value'      => 'value',
     'units'      => 'units');

%Torrus::ReportGenerator::modules =
    ( 'MonthlyUsage' => 'Torrus::ReportGenerator::MonthlySrvUsage' );


%Torrus::ReportOutput::HTML::templates =
    ( 'index'      => 'report-index.html',
      'serviceid'  => 'report-serviceid.html',
      'monthly'    => 'report-monthly.html',
      'yearly'     => 'report-yearly.html');

# Read plugin configurations
{
    my $dir = '@plugtorruscfgdir@';
    opendir(CFGDIR, $dir) or die("Cannot open directory $dir: $!");
    my @files = grep { !/^\./ } readdir(CFGDIR);
    closedir( CFGDIR );
    foreach my $file ( @files )
    {
        require $dir . '/' . $file;
    }
}

    

require '@torrus_siteconfig_pl@';

1;
