#!/usr/bin/env perl
# ctkn.pl - demonstration program for a C-style tokenizer which removes
#   C/C++ comments, does string tokenization, and identifier tokenization.
#   The raw materials are here for processing tokens like ++, +=, ==, etc.,
#   but at present those will be interpreted as two tokens (of type 'id').
#
# To run unit tests:
#   perl -e 'use strict;use warnings;use Carp;require "ctkn.pl";ctkn_UT();'
# With debug:
#   perl -e 'use strict;use warnings;use Carp;require "ctkn.pl";ctkn_UT("d");'
#
# Copyright 2018 Steve Ford (sford@geeky-boy.com) and made available under the
#   Steve Ford's "standard disclaimer, policy, and copyright" notice.  See
#   http://www.geeky-boy.com/steve/standard.html for details.  It means you
#   can do pretty much anything you want with it, including making your own
#   money, but you can't blame me for anything bad that happens.

# Normal public API functions:
#   ctkn_new(option_string) - create new instance of parser.
#     option_string: one or more option characters:
#       c - convert \r, \n, and \t in strings to their control characters.
#       C - Only recognize C comments /*...*/ (tokenize // comments).
#       d - debug prints enabled.
#     Returns: handle to parser instance.
#
#   ctkn_input(ctkn, input_line, loc_string) - feed the parser a line of text
#       to be parsed.
#     ctkn - handle returned by ctkn_new().
#     input_line - line of C code to be parsed.
#     loc_string - nominally file name and line number of input_line.
#
#   ctkn_eof(ctkn) - tell parser the end-of-file was reached.
#     ctkn - handle returned by ctkn_new().
#
#   ctkn_num(ctkn) - returns number of tokens parsed.
#     ctkn - handle returned by ctkn_new().
#
#   ctkn_vals(ctkn) - returns reference to array of token values (see example).
#     ctkn - handle returned by ctkn_new().
#
#   ctkn_types(ctkn) - returns reference to array of token types (see example).
#                      Types are "id", "dqstring" (double quotes), and
#                      "sqstring" (single quotes).
#     ctkn - handle returned by ctkn_new().
#
#   ctkn_locs(ctkn) - returns reference to array of locations for input
#       with column number added (see example).
#     ctkn - handle returned by ctkn_new().
#
#   ctkn_dump(ctkn) - produce a human-readable form of the tokens.
#     ctkn - handle returned by ctkn_new().
#     Returns: string containing dump.
#
# Example:
#   See the function "ctkn_EXAMPLE" at the end of this file.  To run it:
#     perl -e 'require "ctkn.pl";ctkn_EXAMPLE();'


use Carp;
# Module to convert a function pointer to a string (the function name).
use B qw(svref_2object);

# This code implements the parser as a finite state machine.
# The design of the FSM is for the current state to be represented as a
# function pointer.  That function is responsible for taking the current
# input symbol (character) and moving to the next state.


# Create new instance of FSM.
sub ctkn_new {
  my ($options) = @_;
  if (! defined($options)) { $options = ""; }

  my $self = {};  # Alloc a hash for the object.
  $self->{"cur_tok"} = "";        # Accumulator for multi-character tokens.
  $self->{"iline"} = "";
  $self->{"file_line"} = "";
  $self->{"column"} = 0;
  $self->{"state"} = \&ctkn_fsm_idle;

  $self->{"tkn_val"} = [];   # alloc an array
  $self->{"tkn_type"} = [];  # alloc an array
  $self->{"tkn_loc"} = [];   # alloc an array
  $self->{"cur_loc"} = "";

  # Process options.
  ($options =~ /^[dcC]*$/) || croak("Invalid option(s) in '$options' (valid options: d, c)");

  $self->{"esc_n"} = "\\n"; $self->{"esc_r"} = "\\r"; $self->{"esc_t"} = "\\t";
  if ($options =~ /c/) {
    $self->{"esc_n"} = "\n"; $self->{"esc_r"} = "\r"; $self->{"esc_t"} = "\t";
  }

  $self->{"debug"} = 0;
  if ($options =~ /d/) {
    $self->{"debug"} = 1;
  }

  $self->{"C_comments"} = 0;
  if ($options =~ /C/) {
    $self->{"C_comments"} = 1;
  }

  return $self;
}  # ctkn_new


# Function to add a parsed token to the output array.  Not part of public API.
sub ctkn_add {
  my ($self, $tkn_val, $tkn_type) = @_;

  my $tkn_vals = $self->{"tkn_val"};    # array ref
  my $tkn_types = $self->{"tkn_type"};  # array ref
  my $tkn_locs = $self->{"tkn_loc"};    # array ref
  push(@$tkn_vals, $tkn_val);
  push(@$tkn_types, $tkn_type);
  push(@$tkn_locs, $self->{"cur_loc"});
}  # ctkn_add


sub ctkn_err {
  my ($self, $msg) = @_;

  print STDERR "ERR " . $self->{"cur_loc"} . ", $msg\n";
}  # ctkn_err


sub ctkn_dump {
  my ($self) = @_;

  my $tkn_val = $self->{"tkn_val"};    # array ref
  my $tkn_type = $self->{"tkn_type"};  # array ref
  my $tkn_loc = $self->{"tkn_loc"};    # array ref
  my $num_tkns = scalar(@$tkn_val);   # num elements in array

  my $out = "";

  $out .= "num_tkns=$num_tkns\n";
  for (my $i = 0; $i < $num_tkns; $i++) {
    $out .= "i=$i"
      . ", tkn_loc='" . $tkn_loc->[$i]
      . ", tkn_val='" . $tkn_val->[$i]
      . "', tkn_type='" . $tkn_type->[$i]
      . "'\n";
  }

  return $out;
}  # ctkn_dump


# Pass in an input string for parsing.
sub ctkn_input {
  my ($self, $iline, $file_line) = @_;

  my $orig_len = length($iline);
  $self->{"iline"} = $iline;
  $self->{"file_line"} = $file_line;

  while ($self->{"iline"} ne "") {
    # pop first character off string.
    ($self->{"iline"} =~ s/^(.)//s) || croak("ASSERT");
    my $c = $1;
    $self->{"column"} = $orig_len - length($self->{"iline"});
    my $cur_tok = $self->{"cur_tok"};
    my $state = $self->{"state"};
    if ($self->{"debug"}) {
      my $gv = svref_2object($state)->GV;
      print STDERR "ctkn_input: " . $self->{"file_line"} . ":" . $self->{"column"} . ", c='$c', cur_tok='$cur_tok', state=" . $gv->NAME . "\n";
    }
    &$state($self, $c);
  }
}  # ctkn_input


sub ctkn_eof {
  my ($self, $iline) = @_;

  my $state = $self->{"state"};
  &$state($self, "");
}  # ctkn_eof


sub ctkn_num {
  ($self) = @_;

  my $tkn_val = $self->{"tkn_val"};    # array ref
  return scalar(@$tkn_val)
}  # ctkn_num


sub ctkn_vals {
  ($self) = @_;

  return $self->{"tkn_val"};
}  # ctkn_vals


sub ctkn_types {
  ($self) = @_;

  return $self->{"tkn_type"};
}  # ctkn_types


sub ctkn_locs {
  ($self) = @_;

  return $self->{"tkn_loc"};
}  # ctkn_locs


sub ctkn_fsm_idle {
  my ($self, $c) = @_;

  $self->{"cur_loc"} = $self->{"file_line"} . ":" . $self->{"column"};

  if ($c eq "") {  # EOF
    ;  # stay in idle
  }
  elsif ($c =~ /^\\$/) {  # Backslash.
    $self->{"state"} = \&ctkn_fsm_idle_backslash;
  }
  elsif ($c =~ /^[ \t\n]$/) {  # Ignore whitespace.
    ;  # stay in idle
  }
  elsif ($c =~ /^"$/) {  # Start of string.
    $self->{"cur_tok"} = "";
    $self->{"state"} = \&ctkn_fsm_string;
  }
  elsif ($c =~ /^'$/) {  # Start of string.
    $self->{"cur_tok"} = "";
    $self->{"state"} = \&ctkn_fsm_single_quote_string;
  }
  elsif ($c =~ /^\/$/) {  # Start of comment?
    $self->{"cur_tok"} = "";
    $self->{"state"} = \&ctkn_fsm_slash;
  }
  elsif ($c =~ /^[a-zA-Z0-9_.-]$/) {  # Start of id.
    $self->{"cur_tok"} = $c;
    $self->{"state"} = \&ctkn_fsm_id;
  }
  else {  # Special character: a token of its own.
    ctkn_add($self, $c, "id");
  }
}  # ctkn_fsm_idle


sub ctkn_fsm_idle_backslash {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF: the slash wasn't a start of comment; tokenize slash.
    ctkn_add($self, "\\", "id");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^[ \t]$/) {  # Spaces after backslash is non-standard but ok.
    ;  # stay in state
  }
  elsif ($c =~ /^\n$/s) {  # Continuation; ignore backslash,newline.
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  else {  # Escape not supported outside of strings; treat backslash as token.
    ctkn_add($self, "\\", "id");
    ctkn_err($self, "ctkn_fsm_idle_backslash: dubious backslash ($c)");
    # Push the input char back on the string to re-process from idle state.
    $self->{"iline"} = $c . $self->{"iline"};
    $self->{"state"} = \&ctkn_fsm_idle;
  }
}  # ctkn_fsm_idle_backslash


sub ctkn_fsm_slash {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF: the slash wasn't a start of comment; tokenize slash.
    ctkn_add($self, "/", "id");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Backslash.
    $self->{"state"} = \&ctkn_fsm_slash_backslash;
  }
  elsif ($c =~ /^\*$/) {  # Starting a "/*" comment.
    $self->{"cur_tok"} = "";
    $self->{"state"} = \&ctkn_fsm_comment;
  }
  elsif ($c =~ /^\/$/ && ! $self->{"C_comments"}) {
    $self->{"cur_tok"} = "";  # Starting a C++ "//" comment.
    $self->{"state"} = \&ctkn_fsm_cpp_comment;
  }
  else {  # The slash wasn't a start of comment after all; tokenize the slash.
    ctkn_add($self, "/", "id");
    # Push the input char back on the string to re-process from idle state.
    $self->{"iline"} = $c . $self->{"iline"};
    $self->{"state"} = \&ctkn_fsm_idle;
  }
}  # ctkn_fsm_slash


sub ctkn_fsm_slash_backslash {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF: the slash wasn't a start of comment; tokenize slash.
    ctkn_add($self, "/", "id");
    ctkn_add($self, "\\", "id");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^[ \t]$/) {  # Spaces after backslash is non-standard but ok.
    ;  # stay in state
  }
  elsif ($c =~ /^\n$/s) {  # Continuation; ignore backslash.
    $self->{"state"} = \&ctkn_fsm_slash;
  }
  else {  # Escape not supported outside of strings; treat backslash as token.
    ctkn_err($self, "ctkn_fsm_slash_backslash: dubious backslash ($c)");
    ctkn_add($self, "/", "id");
    ctkn_add($self, "\\", "id");
    # Push the input char back on the string to re-process from idle state.
    $self->{"iline"} = $c . $self->{"iline"};
    $self->{"state"} = \&ctkn_fsm_idle;
  }
}  # ctkn_fsm_slash_backslash


sub ctkn_fsm_comment {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Backslash.
    $self->{"state"} = \&ctkn_fsm_comment_backslash;
  }
  elsif ($c =~ /^\*$/) {
    $self->{"state"} = \&ctkn_fsm_comment_ending;
  }
  else {
    ;  # Still in comment, stay in ctkn_fsm_comment.
  }
}  # ctkn_fsm_comment


sub ctkn_fsm_comment_backslash {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Double backslash.
    $self->{"state"} = \&ctkn_fsm_comment;
  }
  else {  # Ignore the backslash.
    # Push the input char back on the string to re-process.
    $self->{"iline"} = $c . $self->{"iline"};
    $self->{"state"} = \&ctkn_fsm_comment;
  }
}  # ctkn_fsm_comment_backslash


sub ctkn_fsm_comment_ending {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Backslash.
    $self->{"state"} = \&ctkn_fsm_comment_ending_backslash;
  }
  elsif ($c =~ /^\/$/) {  # Found */, end of comment.
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  else {
    $self->{"state"} = \&ctkn_fsm_comment;  # Still in comment.
  }
}  # ctkn_fsm_comment_ending


sub ctkn_fsm_comment_ending_backslash {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^[ \t]$/) {  # Spaces after backslash is non-standard but ok.
    ;  # stay in comment_ending_backslash
  }
  elsif ($c =~ /^\n$/s) {  # Continuation; ignore backslash.
    $self->{"state"} = \&ctkn_fsm_comment_ending;
  }
  else {  # Ignore the star,backslash
    $self->{"state"} = \&ctkn_fsm_comment;
  }
}  # ctkn_fsm_comment_ending_backslash


sub ctkn_fsm_cpp_comment {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Backslash.
    $self->{"state"} = \&ctkn_fsm_cpp_comment_backslash;
  }
  elsif ($c =~ /^\n$/s) {  # End of line is end of comment.
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  else {
    ;  # Still in C++ comment.
  }
}  # ctkn_fsm_cpp_comment


sub ctkn_fsm_cpp_comment_backslash {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^[ \t]$/) {  # Spaces after backslash is non-standard but ok.
    ;  # stay in state
  }
  elsif ($c =~ /^\n$/s) {  # Continuation; ignore backslash.
    $self->{"state"} = \&ctkn_fsm_cpp_comment;
  }
  else {  # Ignore backslash.
    $self->{"state"} = \&ctkn_fsm_cpp_comment;
  }
}  # ctkn_fsm_cpp_comment_backslash


sub ctkn_fsm_id {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    ctkn_add($self, $self->{"cur_tok"}, "id");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Backslash.
    $self->{"state"} = \&ctkn_fsm_id_backslash;
  }
  elsif ($c =~ /^[a-zA-Z0-9_.-]$/) {
    $self->{"cur_tok"} .= $c;  # stay in id
  }
  else {  # It wasn't next char of id after all; tokenize the id.
    ctkn_add($self, $self->{"cur_tok"}, "id");
    # Push the input char back on the string to re-process from idle state.
    $self->{"iline"} = $c . $self->{"iline"};
    $self->{"state"} = \&ctkn_fsm_idle;
  }
}  # ctkn_fsm_id


sub ctkn_fsm_id_backslash {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF, treat the backslash as a token
    ctkn_add($self, $self->{"cur_tok"}, "id");
    ctkn_add($self, "\\", "id");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^[ \t]$/) {  # Spaces after backslash is non-standard but ok.
    ;  # stay in state
  }
  elsif ($c =~ /^\n$/s) {  # Continuation; ignore backslash.
    $self->{"state"} = \&ctkn_fsm_id;
  }
  else {  # Escape not supported outside of strings; treat backslash as token.
    ctkn_err($self, "ctkn_fsm_id_backslash: dubious backslash ($c)");
    ctkn_add($self, $self->{"cur_tok"}, "id");
    ctkn_add($self, "\\", "id");
    # Push the input char back on the string to re-process from idle state.
    $self->{"iline"} = $c . $self->{"iline"};
    $self->{"state"} = \&ctkn_fsm_idle;
  }
}  # ctkn_fsm_id_backslash


sub ctkn_fsm_string {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    ctkn_add($self, $self->{"cur_tok"}, "dqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\n$/s) {  # Strings stop at end of line
    ctkn_add($self, $self->{"cur_tok"}, "dqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Escape next character.
    $self->{"state"} = \&ctkn_fsm_string_esc;
  }
  elsif ($c =~ /^"$/) {  # End string.
    ctkn_add($self, $self->{"cur_tok"}, "dqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  else {  # Just a char in the string.
    $self->{"cur_tok"} .= $c;  # stay in ctkn_fsm_string
  }
}  # ctkn_fsm_string


sub ctkn_fsm_string_esc {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    ctkn_add($self, $self->{"cur_tok"}, "dqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Backslash.
    $self->{"state"} = \&ctkn_fsm_string_esc_backslash;
  }
  elsif ($c =~ /^\n$/s) {  # Not a string escape, a line continuation.
    $self->{"state"} = \&ctkn_fsm_string;
  }
  elsif ($c =~ /^n$/) {
    $self->{"cur_tok"} .= $self->{"esc_n"};
    $self->{"state"} = \&ctkn_fsm_string;
  }
  elsif ($c =~ /^r$/) {
    $self->{"cur_tok"} .= $self->{"esc_r"};
    $self->{"state"} = \&ctkn_fsm_string;
  }
  elsif ($c =~ /^t$/) {
    $self->{"cur_tok"} .= $self->{"esc_t"};
    $self->{"state"} = \&ctkn_fsm_string;
  }
  elsif ($c =~ /^[0-7Xx]$/) {
    $self->{"cur_tok"} .= "\\$c";
    $self->{"state"} = \&ctkn_fsm_string;
  }
  elsif ($c =~ /^['"]$/) {  # Escape to normal char.
    $self->{"cur_tok"} .= $c;
    $self->{"state"} = \&ctkn_fsm_string;
  }
  else {  # Dubious escape; maybe one I haven't done yet?
    ###ctkn_err($self, "ctkn_fsm_string_esc: dubious escape '$c'");
    $self->{"cur_tok"} .= $c;
    $self->{"state"} = \&ctkn_fsm_string;
  }
}  # ctkn_fsm_string_esc


sub ctkn_fsm_string_esc_backslash {  # double backslash
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF: escaped backslash.
    $self->{"cur_tok"} .= "\\";
    ctkn_add($self, $self->{"cur_tok"}, "dqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\n$/s) {  # Continuation; ignore backslash.
    $self->{"state"} = \&ctkn_fsm_string_esc;
  }
  elsif ($c =~ /^[ \t]$/) {  # Spaces after backslash is non-standard but ok.
    ;  # stay in string_esc_backslash
  }
  else {  # Escaped backslash
    $self->{"cur_tok"} .= "\\";
    # Push the input char back on the string to re-process from string state.
    $self->{"iline"} = $c . $self->{"iline"};
    $self->{"state"} = \&ctkn_fsm_string;
  }
}  # ctkn_fsm_string_esc_backslash


sub ctkn_fsm_single_quote_string {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    ctkn_add($self, $self->{"cur_tok"}, "sqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\n$/s) {  # Strings stop at end of line
    ctkn_add($self, $self->{"cur_tok"}, "sqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Escape next character.
    $self->{"state"} = \&ctkn_fsm_single_quote_string_esc;
  }
  elsif ($c =~ /^'$/) {  # End string.
    ctkn_add($self, $self->{"cur_tok"}, "sqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  else {  # Just a char in the string.
    $self->{"cur_tok"} .= $c;  # stay in ctkn_fsm_single_quote_string.
  }
}  # ctkn_fsm_single_quote_string


sub ctkn_fsm_single_quote_string_esc {
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF
    ctkn_add($self, $self->{"cur_tok"}, "sqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\\$/) {  # Backslash.
    $self->{"state"} = \&ctkn_fsm_single_quote_string_esc_backslash;
  }
  elsif ($c =~ /^\n$/s) {  # Not a string escape, a line continuation.
    $self->{"state"} = \&ctkn_fsm_single_quote_string;
  }
  elsif ($c =~ /^n$/) {
    $self->{"cur_tok"} .= $self->{"esc_n"};
    $self->{"state"} = \&ctkn_fsm_single_quote_string;
  }
  elsif ($c =~ /^r$/) {
    $self->{"cur_tok"} .= $self->{"esc_r"};
    $self->{"state"} = \&ctkn_fsm_single_quote_string;
  }
  elsif ($c =~ /^t$/) {
    $self->{"cur_tok"} .= $self->{"esc_t"};
    $self->{"state"} = \&ctkn_fsm_single_quote_string;
  }
  elsif ($c =~ /^[0-7Xx]$/) {
    $self->{"cur_tok"} .= "\\$c";
    $self->{"state"} = \&ctkn_fsm_single_quote_string;
  }
  elsif ($c =~ /^['"]$/) {  # Escape to normal char.
    $self->{"cur_tok"} .= $c;
    $self->{"state"} = \&ctkn_fsm_single_quote_string;
  }
  else {  # Dubious escape; maybe one I haven't done yet?
    ###ctkn_err($self, "ctkn_fsm_single_quote_string_esc: dubious escape '$c'");
    $self->{"cur_tok"} .= $c;
    $self->{"state"} = \&ctkn_fsm_single_quote_string;
  }
}  # ctkn_fsm_single_quote_string_esc


sub ctkn_fsm_single_quote_string_esc_backslash {  # double backslash
  my ($self, $c) = @_;

  if ($c eq "") {  # EOF: escaped backslash.
    $self->{"cur_tok"} .= "\\";
    ctkn_add($self, $self->{"cur_tok"}, "sqstring");
    $self->{"state"} = \&ctkn_fsm_idle;
  }
  elsif ($c =~ /^\n$/s) {  # Continuation; ignore backslash.
    $self->{"state"} = \&ctkn_fsm_single_quote_string_esc;
  }
  elsif ($c =~ /^[ \t]$/) {  # Spaces after backslash is non-standard but ok.
    ;  # stay in single_quote_string_esc_backslash
  }
  else {  # Escaped backslash
    $self->{"cur_tok"} .= "\\";
    # Push the input char back on the string to re-process from string state.
    $self->{"iline"} = $c . $self->{"iline"};
    $self->{"state"} = \&ctkn_fsm_single_quote_string;
  }
}  # ctkn_fsm_single_quote_string_esc_backslash


##################################################################################
##################################################################################
# Unit test code.
##################################################################################
##################################################################################


sub ctkn_UT {
  my ($opts) = @_;
  if (! defined($opts)) { $opts = ""; }

  #=======================
  # Test the token buffer first.
  #=======================

  my $ctkn = ctkn_new();
  ctkn_add($ctkn, "abc", "id");
  ctkn_add($ctkn, "123", "int");
  ctkn_add($ctkn, "xyz", "dqstring");

  my $tkn_val = $ctkn->{"tkn_val"};
  (scalar(@$tkn_val) == 3) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[0] eq "abc") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[0] eq "id") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[1] eq "123") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[1] eq "int") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[2] eq "xyz") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[2] eq "dqstring") || croak("FAIL");
  my $out = ctkn_dump($ctkn);
  ($out =~ /^num_tkns=3\ni=0.*string'\n$/s) || croak("FAIL");

  # Test getter functions.
  (ctkn_num($ctkn) == scalar(@$tkn_val)) || croak("FAIL");
  for (my $i = 0; $i < ctkn_num($ctkn); $i++) {
    (ctkn_vals($ctkn)->[$i] == $ctkn->{"tkn_val"}->[$i]) || croak("FAIL");
    (ctkn_types($ctkn)->[$i] == $ctkn->{"tkn_type"}->[$i]) || croak("FAIL");
    (ctkn_locs($ctkn)->[$i] == $ctkn->{"tkn_loc"}->[$i]) || croak("FAIL");
  }

  #=======================
  # Now test the FSM.
  #=======================

  my $ctkn = ctkn_new($opts);
  my $t = 0;

  ctkn_input($ctkn, "ABC X", $t++);
  $tkn_val = $ctkn->{"tkn_val"};
  (scalar(@$tkn_val) == 1) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[0] eq "ABC") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[0] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "YZ", $t++);
  (scalar(@$tkn_val) == 1) || croak("FAIL");

  ctkn_input($ctkn, "/", $t++);
  (scalar(@$tkn_val) == 2) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[0] eq "ABC") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[0] eq "id") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[1] eq "XYZ") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[1] eq "id") || croak("FAIL");

  ctkn_input($ctkn, " ", $t++);
  (scalar(@$tkn_val) == 3) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[2] eq "/") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[2] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "/* a * b / c */ d	", $t++);
  (scalar(@$tkn_val) == 4) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[3] eq "d") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[3] eq "id") || croak("FAIL");

  ctkn_input($ctkn, '"abc \"\txyz"123=', $t++);
  (scalar(@$tkn_val) == 7) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[4] eq 'abc "\\txyz') || croak("FAIL");
  ($ctkn->{"tkn_type"}->[4] eq "dqstring") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[5] eq "123") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[5] eq "id") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[6] eq "=") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[6] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "'ABC \\'\\tXYZ'123=", $t++);
  (scalar(@$tkn_val) == 10) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[7] eq "ABC '\\tXYZ") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[7] eq "sqstring") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[8] eq "123") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[8] eq "id") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[9] eq "=") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[9] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "z", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 11) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[10] eq "z") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[10] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "/* asdf", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 11) || croak("FAIL");

  ctkn_input($ctkn, "/* asdf *", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 11) || croak("FAIL");

  ctkn_input($ctkn, "// asdf \n// fdsa", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 11) || croak("FAIL");

  ctkn_input($ctkn, "\"asdf", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 12) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[11] eq "asdf") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[11] eq "dqstring") || croak("FAIL");

  ctkn_input($ctkn, "\"ASDF\\", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 13) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[12] eq "ASDF") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[12] eq "dqstring") || croak("FAIL");

  ctkn_input($ctkn, '/', $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 14) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[13] eq '/') || croak("FAIL");
  ($ctkn->{"tkn_type"}->[13] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "\\\n\\ 	\nz", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 15) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[14] eq "z") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[14] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "/\\\n* comment */", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 15) || croak("FAIL");

  ctkn_input($ctkn, "/\\ 	 \n* comment */", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 15) || croak("FAIL");

  ctkn_input($ctkn, "/\\", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 17) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[15] eq "/") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[15] eq "id") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[16] eq "\\") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[16] eq "id") || croak("FAIL");

  print STDERR "This next test should print 'dubious backslash'\n";
  ctkn_input($ctkn, "/\\bcd", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 20) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[17] eq "/") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[17] eq "id") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[18] eq "\\") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[18] eq "id") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[19] eq "bcd") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[19] eq "id") || croak("FAIL");
  print STDERR "That test should have printed 'dubious backslash'\n";

  # Not a dubious backslash because its in a comment.
  ctkn_input($ctkn, "/* com\\ment \\*/1", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 21) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[20] eq "1") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[20] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "/* comment *\\/2*/3", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 22) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[21] eq "3") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[21] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "/* comment *\\\n/4", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 23) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[22] eq "4") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[22] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "/* comment *\\ 	 \n/5", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 24) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[23] eq "5") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[23] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "/\\\n/ comment\n// comm\\\nent \n6", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 25) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[24] eq "6") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[24] eq "id") || croak("FAIL");

  print STDERR "This next test should print 'dubious backslash'\n";
  ctkn_input($ctkn, "mn\\\nop\\ 	 \nqr\\s", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 28) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[25] eq "mnopqr") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[25] eq "id") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[26] eq "\\") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[26] eq "id") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[27] eq "s") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[27] eq "id") || croak("FAIL");
  print STDERR "That test should have printed 'dubious backslash'\n";

  ctkn_input($ctkn, "\"\\\\ta\\tb\\\nc\\\"d\\\\\nne\\\\\n\\t\"f", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 30) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[28] eq "\\ta\\tbc\"d\\ne\\t") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[28] eq "dqstring") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[29] eq "f") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[29] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "'\\\\ta\\tb\\\nc\\'d\\\\\nne\\\\\n\\t'f", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 32) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[30] eq "\\ta\\tbc'd\\ne\\t") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[30] eq "sqstring") || croak("FAIL");
  ($ctkn->{"tkn_val"}->[31] eq "f") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[31] eq "id") || croak("FAIL");

  ctkn_input($ctkn, "'asdf", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 33) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[32] eq "asdf") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[32] eq "sqstring") || croak("FAIL");

  ctkn_input($ctkn, "'ASDF\\", $t++);
  ctkn_eof($ctkn);
  (scalar(@$tkn_val) == 34) || croak("FAIL");
  ($ctkn->{"tkn_val"}->[33] eq "ASDF") || croak("FAIL");
  ($ctkn->{"tkn_type"}->[33] eq "sqstring") || croak("FAIL");

  print STDERR ctkn_dump($ctkn);

  print STDERR "Unit test: SUCCESS!\n";
}  # ctkn_UT


# Example usage of ctkn.  To run it:
#   perl -e 'require "ctkn.pl";ctkn_EXAMPLE();'

sub ctkn_EXAMPLE {
# A perl program outside this file should start like this:
#   use strict;
#   use warnings;
#   require "ctkn.pl";

  my $c = ctkn_new();
  ctkn_input($c, "count++", "x");
  ctkn_eof($c);

  print ctkn_num($c) . "\n";         # prints '3'

  print ctkn_vals($c)->[0] . "\n";   # prints 'count'
  print ctkn_types($c)->[0] . "\n";  # prints 'id'
  print ctkn_locs($c)->[0] . "\n";   # prints 'x:1'

  print ctkn_vals($c)->[1] . "\n";   # prints '+'
  print ctkn_types($c)->[1] . "\n";  # prints 'id'
  print ctkn_locs($c)->[1] . "\n";   # prints 'x:6'

  print ctkn_vals($c)->[2] . "\n";   # prints '+'
  print ctkn_types($c)->[2] . "\n";  # prints 'id'
  print ctkn_locs($c)->[2] . "\n";   # prints 'x:7'
}  # ctkn_EXAMPLE


1;
