# $Id: PoeBuildInfo.pm 2147 2006-11-02 20:06:03Z bsmith $

# Build information for POE.  Moved into a library so it can be
# required by Makefile.PL and gen-meta.perl.

package PoeBuildInfo;

use strict;

use Exporter;
use base qw(Exporter);
use vars qw(@EXPORT_OK);

@EXPORT_OK = qw(
  TEST_FILES
  CLEAN_FILES
  CORE_REQUIREMENTS
  DIST_ABSTRACT
  DIST_AUTHOR
  RECOMMENDED_TIME_HIRES
);

sub CORE_REQUIREMENTS () {
  (
    "Carp"               => 0,
    "Errno"              => 1.09,
    "Exporter"           => 0,
    "File::Spec"         => 0.87,
    "IO"                 => 1.20,
    "POSIX"              => 1.02,
    "Socket"             => 1.7,
    "Test::Harness"      => 2.26,
    (
      ($^O eq "MSWin32")
      ? (
        "Win32::Console" => 0.031,
        "Win32API::File" => 0.05,
      )
      : ()
    ),
  )
}

sub RECOMMENDED_TIME_HIRES () {
  ( "Time::HiRes" => 1.59 )
}

sub DIST_AUTHOR () {
  ( 'Rocco Caputo <rcaputo@cpan.org>' )
}

sub DIST_ABSTRACT () {
  ( 'A portable networking and multitasking framework.' )
}

sub CLEAN_FILES () {
  my @clean_files = qw(
    coverage.report
    poe_report.xml
    run_network_tests
    test-output.err
    t/20_resources/10_perl
    t/20_resources/10_perl/*
    t/20_resources/20_xs
    t/20_resources/20_xs/*
    t/30_loops/10_select
    t/30_loops/10_select/*
    t/30_loops/20_poll
    t/30_loops/20_poll/*
    t/30_loops/30_event
    t/30_loops/30_event/*
    t/30_loops/40_gtk
    t/30_loops/40_gtk/*
    t/30_loops/50_tk
    t/30_loops/50_tk/*
  );
  "@clean_files";
}

sub TEST_FILES () {
  my @test_files = qw(
    t/*.t
    t/*/*.t
    t/*/*/*.t
  );
  "@test_files";
}

1;
