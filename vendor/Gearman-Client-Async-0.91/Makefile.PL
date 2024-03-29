use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'Gearman::Client::Async',
    VERSION_FROM => 'lib/Gearman/Client/Async.pm', # finds $VERSION
    PREREQ_PM    => {
                     'Test::Simple' => 0.44,
                     Danga::Socket  => 1.52,
                     Gearman::Client => 1.01,
                    },
    ( $] >= 5.005 ?
      (
        AUTHOR       => 'Brad Fitzpatrick (brad@danga.org), Jonathan Steinert (hachi@cpan.org)',
        ABSTRACT_FROM => 'lib/Gearman/Client/Async.pm',
      ) : ()),
    dist => {
      COMPRESS => 'gzip -9',
      SUFFIX   => 'gz',
      PREOP    => q{pod2text lib/Gearman/Client/Async.pm > ./$(DISTNAME)-$(VERSION)/README},
    },
);
