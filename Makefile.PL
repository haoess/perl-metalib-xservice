use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'MetaLib::XService',
    AUTHOR              => 'Frank Wiegand <frank.wiegand@gmail.com>',
    VERSION_FROM        => 'lib/MetaLib/XService.pm',
    ABSTRACT_FROM       => 'lib/MetaLib/XService.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'LWP::UserAgent' => 0,
        'XML::LibXML' => 0,
        'XML::Simple' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'MetaLib-XService-*' },
);
