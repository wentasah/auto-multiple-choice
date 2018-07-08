#! /usr/bin/perl
#
# Copyright (C) 2012-2017 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

my @dirs=@ARGV;

print q$<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Auto Multiple Choice Documentation</title><link rel="stylesheet" href="style.css" type="text/css" /></head>
<body>
<h2 class="title">Auto Multiple Choice Documentation</h2>
<p>Available languages:$;

for my $d (sort { $a cmp $b } @dirs) {
  my $rel=$d;
  $rel =~ s/.*\///;
  my $lang=$rel;
  $lang =~ s/.*\.//;
  print " <a href=\"$rel/index.html\">".uc($lang)."</a>";
}

print q$</p></body></html>
$;
