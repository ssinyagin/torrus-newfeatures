# This is the Torrus-specific profile for Perl::Critic
# The defaults are sometimes too demanding and require too much effort to fix,
# so this profile proposes a certain compromise.

severity  = 3

# Package vars are used a lot in torrus
[Variables::ProhibitPackageVars]
severity = 1

# Complexity is fine as long as it's designed properly :)
[Modules::ProhibitExcessMainComplexity]
severity = 1

[Subroutines::ProhibitExcessComplexity]
severity = 1

[ControlStructures::ProhibitDeepNests]
severity = 1


# there is a lot of whitespace garbage, but removing all of it will make
# the code unmanageable
[CodeLayout::ProhibitTrailingWhitespace]
severity = 1

# Tabs are bad
[CodeLayout::ProhibitHardTabs]
severity = 5

# torrus-coonfig.pl is explicitly require'd
[Modules::RequireBarewordIncludes]
severity = 1

# new Object() is used everywhere
[Objects::ProhibitIndirectSyntax]
severity = 1


# if-elsif-elsif-elsif are used in a couple of files
[ControlStructures::ProhibitCascadingIfElse]
severity = 1


# they tell to use /x in every regexp, but we don't
[RegularExpressions::RequireExtendedFormatting]
severity = 1


# we use "my %options = @_;" in new() constructors, probably need to
# change that later
[Subroutines::RequireArgUnpacking]
severity = 2

# We use return undef very often as an indication that the value is undefined.
[Subroutines::ProhibitExplicitReturnUndef]
severity = 1

# string eval is used rarely and in places where we really need it
[BuiltinFunctions::ProhibitStringyEval]
severity = 1

# using oct(664) is just odd. Everyone knows what leading zero means
[ValuesAndExpressions::ProhibitLeadingZeros]
severity = 1

# global signal handling is critical for correct BerkeleyDB functioning
# also $0 is needed to set the process status
[Variables::RequireLocalizedPunctuationVars]
allow = %SIG $0

# we've got a few subroutines with too many arguments
[Subroutines::ProhibitManyArgs]
max_arguments = 7

# maybe I should change it later
[ErrorHandling::RequireCarping]
severity = 1

