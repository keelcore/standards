#!/usr/bin/env perl
# scripts/lib/rewrite-paths.pl
# rewrite-paths.pl MAP FILE...: in each FILE, every old path of MAP (old<TAB>new lines, # comments) becomes its
# new path, where it stands as a whole path (not part of a longer name). CHANGELOG.md keeps its released
# sections as written: only the text before its first "## [<version>]" heading changes. Prints each FILE
# changed. Used by scripts/refresh-governance.sh.
use strict;
use warnings;

my $map = shift @ARGV or die "usage: rewrite-paths.pl MAP FILE...\n";
open(my $m, '<', $map) or die "$map: $!\n";
my @pairs;
while (my $line = <$m>) {
  chomp $line;
  next if $line =~ /^\s*(#|$)/;
  my ($old, $new) = split /\t/, $line;
  push @pairs, [$old, $new] if defined $new && $new ne '';
}
close $m;

for my $file (@ARGV) {
  open(my $h, '<', $file) or next;
  local $/;
  my $text = <$h>;
  close $h;
  my ($head, $tail) = ($text, '');
  if ($file =~ m{(^|/)CHANGELOG\.md$} && $text =~ /\A(.*?)(\n## \[\d.*)\z/s) {
    ($head, $tail) = ($1, $2);
  }
  my $changed = $head;
  for my $pair (@pairs) {
    my ($old, $new) = @$pair;
    $changed =~ s/(?<![A-Za-z0-9_.-])\Q$old\E(?![A-Za-z0-9_-])/$new/g;
  }
  next if $changed eq $head;
  open(my $w, '>', $file) or die "$file: $!\n";
  print $w $changed . $tail;
  close $w;
  print "$file\n";
}
