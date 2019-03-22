#!/usr/bin/perl
#
# epn-utils.pm
# Eric Nawrocki
# EPN, Tue Mar 19 13:35:06 2019
# version: 0.00
#
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

require "epn-ofile.pm";

#####################################################################
# Data structures used in this module:
#
#####################################################################
# List of subroutines:
# 
#################################################################
# Subroutine: utl_RunCommand()
# Incept:     EPN, Thu Feb 11 13:32:34 2016 [dnaorg.pm]
#
# Purpose:     Runs a command using system() and exits in error 
#              if the command fails. If $be_verbose, outputs
#              the command to stdout. If $FH_HR->{"cmd"} is
#              defined, outputs command to that file handle.
#
# Arguments:
#   $cmd:         command to run, with a "system" command;
#   $be_verbose:  '1' to output command to stdout before we run it, '0' not to
#   $do_failok:   '1' to NOT exit if command fails, '0' to exit if command fails
#   $FH_HR:       REF to hash of file handles, including "cmd"
#
# Returns:    amount of time the command took, in seconds
#
# Dies:       if $cmd fails and $do_failok is '0'
#################################################################
sub utl_RunCommand {
  my $sub_name = "utl_RunCommand()";
  my $nargs_expected = 4;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($cmd, $be_verbose, $do_failok, $FH_HR) = (@_);
  
  my $cmd_FH = undef;
  if(defined $FH_HR && defined $FH_HR->{"cmd"}) { 
    $cmd_FH = $FH_HR->{"cmd"};
  }

  if($be_verbose) { 
    print ("Running cmd: $cmd\n"); 
  }

  if(defined $cmd_FH) { 
    print $cmd_FH ("$cmd\n");
  }

  my ($seconds, $microseconds) = gettimeofday();
  my $start_time = ($seconds + ($microseconds / 1000000.));

  system($cmd);

  ($seconds, $microseconds) = gettimeofday();
  my $stop_time = ($seconds + ($microseconds / 1000000.));

  if(($? != 0) && (! $do_failok)) { 
    ofile_FAIL("ERROR in $sub_name, the following command failed:\n$cmd\n", $?, $FH_HR); 
  }

  return ($stop_time - $start_time);
}

#################################################################
# Subroutine: utl_ArrayOfHashesToArray()
# Incept:     EPN, Wed Mar 20 09:07:06 2019
#
# Purpose:    Fill @{$AR} with all values in $AHR->[]{$key}.
# Arguments:
#   $AHR:      REF to array of hashes
#   $AR:       REF to array to add to
#   $key:      key of interest
# 
# Returns: number of elements added to @{$AR}
#
#################################################################
sub utl_ArrayOfHashesToArray {
  my $sub_name = "utl_ArrayOfHashesToArray()";
  my $nargs_expected = 3;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
 
  my ($AHR, $AR, $key) = (@_);

  my $ret_n = 0;
  my $n = scalar(@{$AHR});
  for(my $i = 0; $i < $n; $i++) { 
    if(defined $AHR->[$i]{$key}) { 
      push(@{$AR}, $AHR->[$i]{$key}); 
      $ret_n++;
    }
  }
  
  return $ret_n;
}

#################################################################
# Subroutine:  utl_ConcatenateListOfFiles()
# Incept:      EPN, Sun Apr 24 08:08:15 2016
#
# Purpose:     Concatenate a list of files into one file.
#              If the list has more than 500 files, split
#              up job into concatenating 500 at a time.
# 
#              We remove all files that we concatenate unless
#              --keep option is on in %{$opt_HHR}.
#
# Arguments: 
#   $file_AR:          REF to array of all files to concatenate
#   $outfile:          name of output file to create by concatenating
#                      all files in @{$file_AR}.
#   $caller_sub_name:  name of calling subroutine (can be undef)
#   $opt_HHR:          REF to 2D hash of option values, see top of epn-options.pm for description
#   $FH_HR:            ref to hash of file handles
# 
# Returns:     Nothing.
# 
# Dies:        If one of the cat commands fails.
#              If $outfile is in @{$file_AR}
#              If @{$file_AR} contains more than 800*800 files
#              (640K) if so, we may need to call this function
#              recursively twice (that is, recursive call will
#              also call itself recursively) and we don't have 
#              a sophisticated enough temporary file naming
#              strategy to handle that robustly.
################################################################# 
sub utl_ConcatenateListOfFiles { 
  my $nargs_expected = 5;
  my $sub_name = "utl_ConcatenateListOfFiles()";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
  my ($file_AR, $outfile, $caller_sub_name, $opt_HHR, $FH_HR) = (@_);

  if(utl_AFindNonNumericValue($file_AR, $outfile, $FH_HR) != -1) { 
    ofile_FAIL(sprintf("ERROR in $sub_name%s, output file name $outfile exists in list of files to concatenate", 
                        (defined $caller_sub_name) ? " called by $caller_sub_name" : ""), "dnaorg", 1, $FH_HR);
  }

  # first, convert @{$file_AR} array into a 2D array of file names, each of which has 
  # a max of 800 elements, we'll concatenate each of these lists separately
  my $max_nfiles = 800;
  my $nfiles = scalar(@{$file_AR});

  if($nfiles > ($max_nfiles * $max_nfiles)) { 
    ofile_FAIL(sprintf("ERROR in $sub_name%s, trying to concatenate %d files, our limit is %d", 
                       (defined $caller_sub_name) ? " called by $caller_sub_name" : "", $nfiles, $max_nfiles * $max_nfiles), 
               undef, 1, $FH_HR);
  }
    
  my ($idx1, $idx2); # indices in @{$file_AR}, and of secondary files
  my @file_AA = ();
  $idx2 = -1; # get's incremented to 0 in first loop iteration
  for($idx1 = 0; $idx1 < $nfiles; $idx1++) { 
    if(($idx1 % $max_nfiles) == 0) { 
      $idx2++; 
      @{$file_AA[$idx2]} = (); # initialize
    }
    push(@{$file_AA[$idx2]}, $file_AR->[$idx1]);
  }
  
  my $nconcat = scalar(@file_AA);
  my @tmp_outfile_A = (); # fill this with names of temporary files we create
  my $tmp_outfile; # name of an output file we'll create
  for($idx2 = 0; $idx2 < $nconcat; $idx2++) { 
    if($nconcat == 1) { # special case, we don't need to create any temporary files
      $tmp_outfile = $outfile;
    }
    else { 
      $tmp_outfile = $outfile . ".tmp" . ($idx2+1); 
      # make sure this file does not exist in @{$file_AA[$idx2]} to avoid klobbering
      # if it does, continue to append .tmp($idx2+1) until it doesn't
      while(utl_AFindNonNumericValue($file_AA[$idx2], $tmp_outfile, $FH_HR) != -1) { 
        $tmp_outfile .= ".tmp" . ($idx2+1); 
      }
    }
    # create the concatenate command
    my $cat_cmd = "cat ";
    foreach my $tmp_file (@{$file_AA[$idx2]}) {
      $cat_cmd .= $tmp_file . " ";
    }
    $cat_cmd .= "> $tmp_outfile";

    # execute the command
    utl_RunCommand($cat_cmd, opt_Get("-v", $opt_HHR), 0, $FH_HR);

    # add it to the array of temporary files
    push(@tmp_outfile_A, $tmp_outfile); 
  }

  if(scalar(@tmp_outfile_A) > 1) { 
    # we created more than one temporary output file, concatenate them
    # by calling this function again
    utl_ConcatenateListOfFiles(\@tmp_outfile_A, $outfile, (defined $caller_sub_name) ? $caller_sub_name . ":" . $sub_name : $sub_name, $opt_HHR, $FH_HR);
  }

  if(! opt_Get("--keep", $opt_HHR)) { 
    # remove all of the original files, be careful to not remove @tmp_outfile_A
    # because the recursive call will handle that
    foreach my $file_to_remove (@{$file_AR}) { 
      utl_FileRemoveUsingSystemRm($file_to_remove, 
                                  (defined $caller_sub_name) ? $caller_sub_name . ":" . $sub_name : $sub_name, 
                                  $opt_HHR, $FH_HR);
    }
  }

  return;
}

#################################################################
# Subroutine:  utl_AFindNonNumericValue()
# Incept:      EPN, Tue Feb 16 10:40:57 2016 [dnaorg.pm]
#
# Purpose:     Returns (first) index in @{$AR} that has the 
#              nonnumeric value $value. Returns -1 
#              if it does not exist.
#
# Arguments: 
#   $AR:       REF to array 
#   $value:    the value we're checking exists in @{$AR}
#   $FH_HR:    REF to hash of file handles, including "log" and "cmd"
# 
# Returns:     index ($i) '1' if $value exists in @{$AR}, '-1' if not
#
# Dies:        if $value is numeric, or @{$AR} is not defined.
################################################################# 
sub utl_AFindNonNumericValue { 
  my $nargs_expected = 3;
  my $sub_name = "utl_AFindNonNumericValue()";
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($AR, $value, $FH_HR) = (@_);

  if(verify_real($value)) { 
    ofile_FAIL("ERROR in $sub_name, value $value seems to be numeric, we can't compare it for equality", undef, 1, $FH_HR);
  }

  if(! defined $AR) { 
    ofile_FAIL("ERROR in $sub_name, array reference is not defined", undef, 1, $FH_HR);
  }

  for(my $i = 0; $i < scalar(@{$AR}); $i++) {
    if($AR->[$i] eq $value) { 
      return $i; 
    }
  }

  return -1; # did not find it
}

#################################################################
# Subroutine: utl_FileRemoveUsingSystemRm
# Incept:     EPN, Fri Mar  4 15:57:25 2016 [dnaorg.pm]
#
# Purpose:    Remove a file from the filesystem by using
#             the system rm command.
# Arguments:
#   $file:            file to remove
#   $caller_sub_name: name of caller, can be undef
#   $opt_HHR:         REF to 2D hash of option values, see top of epn-options.pm for description
#   $FH_HR:           REF to hash of file handles, including "log" and "cmd"
# 
# Returns: void
#
# Dies:    - if the file does not exist
#
#################################################################
sub utl_FileRemoveUsingSystemRm {
  my $sub_name = "utl_FileRemoveUsingSystemRm";
  my $nargs_expected = 4;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
 
  my ($file, $caller_sub_name, $opt_HHR, $FH_HR) = (@_);
  
  if(! -e $file) { 
    ofile_FAIL(sprintf("ERROR in $sub_name, %s trying to remove file $file but it does not exist", 
                (defined $caller_sub_name) ? "called by $caller_sub_name," : 0), "dnaorg", 1, $FH_HR); 
  }

  utl_RunCommand("rm $file", opt_Get("-v", $opt_HHR), 0, $FH_HR);

  return;
}

#################################################################
# Subroutine:  utl_RemoveDirPath()
# Incept:      EPN, Mon Nov  9 14:30:59 2009 [ssu-align]
#
# Purpose:     Given a full path of a file remove the directory path.
#              For example: "foodir/foodir2/foo.stk" becomes "foo.stk".
#
# Arguments: 
#   $fullpath: name of original file
# 
# Returns:     The string $fullpath with dir path removed.
#
################################################################# 
sub utl_RemoveDirPath {
  my $sub_name = "utl_RemoveDirPath()";
  my $nargs_expected = 1;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($fullpath) = (@_);

  $fullpath =~ s/^.+\///;

  return $fullpath;
}

#################################################################
# Subroutine:  utl_HHFromAH()
# Incept:      EPN, Fri Mar 22 09:43:34 2019
#
# Purpose:     Create a 2D hash %{$HHR} from an array of hashes
#              @{$AHR}.
#              First dim keys in %{$HHR} will be values from 
#              $AHR->[]{$AH_key_for_HH_key}.
#              Second dim keys in %{$HHR} will be all other keys from
#              $AHR->[]{}.
#              
# Arguments: 
#   $HHR:               ref to 2D hash to create
#   $AHR:               ref to array of hashes to copy from
#   $AH_key_for_HH_key: key in @{$AHR} to get to use value from to use
#                       as key in 1st dim of %{$HHR}
#   $call_str:          string describing caller, to output if we die
#   $FH_HR:             ref to hash of file handles, including "log" and "cmd"
# 
# Returns:     void
# 
# Dies:        If not all elements of @{$AHR} have 
#              $AHR->[]{$AH_key_for_HH_key} defined. 
#              If more than one elements of @{$AHR} have same
#              value for @{$AHR->[]{$key}}.
#
################################################################# 
sub utl_HHFromAH {
  my $sub_name = "utl_HHFromAH()";
  my $nargs_expected = 4;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
 
  my ($HHR, $AHR, $AH_key_for_HH_key, $call_str, $FH_HR) = (@_);

  %{$HHR} = ();
  my $n = scalar(@{$AHR});
  my $AH_value_for_HH_key = undef;
  for(my $i = 0; $i < $n; $i++) { 
    if(! defined $AHR->[$i]{$AH_key_for_HH_key}) {
      ofile_FAIL("ERROR in $sub_name,%selement $i does not have key $AH_key_for_HH_key", 
                 (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
    }
    $AH_value_for_HH_key = $AHR->[$i]{$AH_key_for_HH_key};
    if(defined $HHR->{$AH_value_for_HH_key}) { 
      ofile_FAIL("ERROR in $sub_name,%stwo elements have same value for $AH_key_for_HH_key key ($AH_value_for_HH_key)", 
                 (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
    }
    %{$HHR->{$AH_value_for_HH_key}} = ();
    foreach my $AH_key2_for_HH_key (keys (%{$AHR->[$i]})) { 
      if($AH_key2_for_HH_key ne $AH_key_for_HH_key) { 
        $HHR->{$AH_value_for_HH_key}{$AH_key2_for_HH_key} = $AHR->[$i]{$AH_key2_for_HH_key};
      }
    }
  }

  return;
}

#################################################################
# Subroutine:  utl_HHFromAHAddIdx()
# Incept:      EPN, Thu Mar 21 06:35:28 2019
#
# Purpose:     Create a 2D hash %{$HHR} from an array of hashes
#              @{$AHR} by calling utL_HHFromAH() 
#              (see that sub's Purpose for more details)
#              
#              And then add $HHR->{$key}{"idx"}, that gives index <i> of 
#              @{$AHR} for which $AHR->[<i>]{$AH_key_for_HH_key} == $key.
#              
# Arguments: 
#   $HHR:               ref to 2D hash to create
#   $AHR:               ref to array of hashes to copy from
#   $AH_key_for_HH_key: key in @{$AHR} to get to use value from to use
#                       as key in 1st dim of %{$HHR}
#   $call_str:          string describing caller, to output if we die
#   $FH_HR:             ref to hash of file handles, including "log" and "cmd"
# 
# Returns:     void
# 
# Dies:        If not all elements of @{$AHR} have 
#              $AHR->[]{$AH_key_for_HH_key} defined. 
#              If more than one elements of @{$AHR} have same
#              value for @{$AHR->[]{$key}}.
#              If $AHR->[]{"idx"} is defined for any element.
#              If $AH_key_for_HH_key is "idx";
#
################################################################# 
sub utl_HHFromAHAddIdx {
  my $sub_name = "utl_HHFromAHAddIdx()";
  my $nargs_expected = 4;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
 
  my ($HHR, $AHR, $AH_key_for_HH_key, $call_str, $FH_HR) = (@_);

  # make sure "idx" is not the $AH_key_for_HH_key
  if($AH_key_for_HH_key eq "idx") { 
    ofile_FAIL("ERROR in $sub_name,%skey to choose is \"idx\"", 
               (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
  }
  # make sure "idx" 2D key does not exist for any element
  my $n = scalar(@{$AHR});
  for(my $i = 0; $i < $n; $i++) { 
    if(defined $AHR->[$i]{"idx"}) {
      ofile_FAIL("ERROR in $sub_name,%selement $i already has key \"idx\" upon entry", 
                 (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
    }
  }

  # do most of the work with utl_HHFromAH
  utl_HHFromAH($HHR, $AHR, $AH_key_for_HH_key, $call_str, $FH_HR);

  # add idx 
  my $AH_value_for_HH_key = undef;
  for(my $i = 0; $i < $n; $i++) { 
    $AH_value_for_HH_key = $AHR->[$i]{$AH_key_for_HH_key};
    $HHR->{$AH_value_for_HH_key}{"idx"} = $i;
  }

  return;
}

#################################################################
# Subroutine:  utl_HFromAH()
# Incept:      EPN, Fri Mar 22 06:20:18 2019
#
# Purpose:     Create a 1D hash %{$HR} using key/value pairs
#              from @{$AHR}. 
#              Keys in %{$HR} will be values from 
#              $AHR->[]{$AH_key_for_H_key}.
#              Values in %{$HR} will be values from 
#              $AHR->[]{$AH_key_for_H_value}.
#              
# Arguments: 
#   $HR:                  ref to 1D hash to create
#   $AHR:                 ref to array of hashes to copy from
#   $AH_key_for_H_key:    key in @{$AHR} to get value from to use as key in %{$HR}
#   $AH_key_for_H_value:  key in @{$AHR} to get value from to use as value in %{$HR}
#   $call_str:            string describing caller, to output if we die
#   $FH_HR:               ref to hash of file handles, including "log" and "cmd"
# 
# Returns:     void
# 
# Dies:        If not all elements of @{$AHR} have 
#              $AHR->[]{$AH_key_for_H_key}}
#              If not all elements of @{$AHR} have 
#              $AHR->[]{$AH_key_for_H_value}}
#              If more than one elements of @{$AHR} have same
#              value for @{$AHR->[]{$AH_key_for_H_key}}.
#
################################################################# 
sub utl_HFromAH {
  my $sub_name = "utl_HFromAH()";
  my $nargs_expected = 6;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
 
  my ($HR, $AHR, $AH_key_for_H_key, $AH_key_for_H_value, $call_str, $FH_HR) = (@_);

  printf("in $sub_name, call_str: $call_str\n");

  %{$HR} = ();
  my $n = scalar(@{$AHR});
  my $AH_value_for_H_key = undef;
  for(my $i = 0; $i < $n; $i++) { 
    if(! defined $AHR->[$i]{$AH_key_for_H_key}) { 
      ofile_FAIL("ERROR in $sub_name,%selement $i does not have key $AH_key_for_H_key", 
                 (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
    }
    if(! defined $AHR->[$i]{$AH_key_for_H_value}) { 
      ofile_FAIL("ERROR in $sub_name,%selement $i does not have key $AH_key_for_H_value", 
                 (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
    }
    my $H_key   = $AHR->[$i]{$AH_key_for_H_key};
    my $H_value = $AHR->[$i]{$AH_key_for_H_value};
    if(defined $HR->{$H_key}) { 
      ofile_FAIL("ERROR in $sub_name,%stwo elements have same value for key $AH_key_for_H_key ($H_key)", 
                 (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
    }
    $HR->{$H_key} = $H_value;
  }

  return;
}

#################################################################
# Subroutine:  utl_IdxHFromA()
# Incept:      EPN, Fri Mar 22 10:01:38 2019
#
# Purpose:     Create a 1D 'index' hash %{$idx_HR} such that
#              $idx_HR->{$key} == $i if
#              $AR->[$i] == $key
#              from @{$AHR}. 
#              
# Arguments: 
#   $idx_HR:              ref to 1D hash to create
#   $AR:                  ref to array
#   $call_str:            string describing caller, to output if we die
#   $FH_HR:               ref to hash of file handles, including "log" and "cmd"
# 
# Returns:     void
# 
# Dies:        Two elements of @{$AR} are identical:
#              (if AR->[$i] == AR->[$j] and $i != $j for any $i, $j)
#
################################################################# 
sub utl_IdxHFromA {
  my $sub_name = "utl_IdxHFromA()";
  my $nargs_expected = 4;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
 
  my ($HR, $AR, $call_str, $FH_HR) = (@_);

  %{$HR} = ();
  my $n = scalar(@{$AR});
  for(my $i = 0; $i < $n; $i++) { 
    my $key = $AR->[$i];
    if(defined $HR->{$key}) { 
      ofile_FAIL("ERROR in $sub_name,%stwo elements in array have same value ($key)",
                 (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
    }
    $HR->{$key} = $i;
  }

  return;
}

#################################################################
# Subroutine:  utl_IdxHFromAH()
# Incept:      EPN, Fri Mar 22 10:01:38 2019
#
# Purpose:     Create a 1D 'index' hash %{$idx_HR} from @{$AHR} 
#              such that
#              $idx_HR->{$key} == $i if
#              $AHR->[$i]{$AH_key} == $key
#              
# Arguments: 
#   $idx_HR:              ref to 1D hash to create
#   $AHR:                 ref to hash of arrays
#   $AH_key:              ref to key in %{$AHR->[$i]}
#   $call_str:            string describing caller, to output if we die
#   $FH_HR:               ref to hash of file handles, including "log" and "cmd"
# 
# Returns:     void
# 
# Dies:        Two values we are trying to add as keys to %{$idx_HR} are identical
#              (if AHR->[$i]{$AH_key} == AHR->[$j]{$AH_key} and $i != $j for any $i, $j)
#              If AHR->[$i]{$AH_key} is undefined for any $i
################################################################# 
sub utl_IdxHFromAH {
  my $sub_name = "utl_IdxHFromAH()";
  my $nargs_expected = 5;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
 
  my ($HR, $AHR, $AH_key, $call_str, $FH_HR) = (@_);

  %{$HR} = ();
  my $n = scalar(@{$AHR});
  for(my $i = 0; $i < $n; $i++) { 
    if(! defined $AHR->[$i]{$AH_key}) { 
      ofile_FAIL("ERROR in $sub_name,%shash that is array element $i does not have key $AH_key",
                 (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
    }
    my $H_key = $AHR->[$i]{$AH_key};
    if(defined $HR->{$H_key}) { 
      ofile_FAIL("ERROR in $sub_name,%stwo elements of source array of hashes we are trying to use as keys in destination hash have same value ($H_key)",
                 (defined $call_str) ? "$call_str" : "", undef, 1, $FH_HR); 
    }
    $HR->{$H_key} = $i;
  }

  return;
}

#################################################################
# Subroutine: utl_AHCountKeyValue()
# Incept:     EPN, Tue Mar 19 11:37:32 2019
#
# Synopsis: Return the number of elements in @{AHR} that 
#           have a key $key in %{$AHR->[]} with value $value.
#
# Arguments:
#  $AHR:      ref to array of hashes
#  $key:      hash key
#  $value:    hash value
#
# Returns:    Number of array elements for which $AHR->[]{$key} eq $value
#
#################################################################
sub utl_AHCountKeyValue {
  my $sub_name = "utl_AHCountKeyValue";
  my $nargs_expected = 3;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 

  my ($AHR, $key, $value) = (@_);

  my $ret_n = 0;
  for(my $i = 0; $i < scalar(@{$AHR}); $i++) { 
    # printf("in $sub_name: AHR->[$i]{$key} $AHR->[$i]{$key}\n");
    if((defined $AHR->[$i]{$key}) && 
       ($AHR->[$i]{$key} eq $value)) { 
      $ret_n++;
    }
  }

  # printf("in $sub_name: returning $ret_n\n");
  return $ret_n;
}

#################################################################
# Subroutine: utl_AHValidate()
# Incept:     EPN, Wed Mar 13 13:24:38 2019
#
# Purpose:    Validate an array of hashes, by making sure it
#             includes a key/value for all keys in @{$keys_AR}.
# Arguments:
#   $AHR:      REF to array of hashes to validate
#   $keys_AR:  REF to array of keys that may be excluded from the hash
#   $fail_str: extra string to output if we die
#   $FH_HR:    REF to hash of file handles, including "log" and "cmd"
# 
# Returns: scalar(@{$AHR});
#
# Dies:    - if one of the keys in @{$keys_AR} does not exist in all hashes
#            of the array
#
#################################################################
sub utl_AHValidate {
  my $sub_name = "utl_AHValidate()";
  my $nargs_expected = 4;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
 
  my ($AHR, $keys_AR, $fail_str, $FH_HR) = (@_);

  my $n = scalar(@{$AHR});

  for(my $i = 0; $i < $n; $i++) { 
    utl_HValidate($AHR->[$i], $keys_AR, $fail_str, $FH_HR);
  }

  return $n;
}

#################################################################
# Subroutine: utl_HValidate()
# Incept:     EPN, Fri Mar 15 09:37:19 2019
#
# Purpose:    Validate a hash, by making sure a defined value
#             exists for each key in @{$keys_AR}.
# Arguments:
#   $HR:       REF to the hash
#   $keys_AR:  REF to array of keys that may be excluded from the hash
#   $fail_str: extra string to output if we die
#   $FH_HR:    REF to hash of file handles, including "log" and "cmd"
# 
# Returns: void
#
# Dies:    - if one of the keys in @{$keys_AR} does not exist in the hash
#            of the array
#
#################################################################
sub utl_HValidate {
  my $sub_name = "utl_HValidate()";
  my $nargs_expected = 4;
  if(scalar(@_) != $nargs_expected) { printf STDERR ("ERROR, $sub_name entered with %d != %d input arguments.\n", scalar(@_), $nargs_expected); exit(1); } 
 
  my ($HR, $keys_AR, $fail_str, $FH_HR) = (@_);

  foreach my $key (@{$keys_AR}) { 
    if(! exists $HR->{$key}) { 
      ofile_FAIL(sprintf("ERROR in $sub_name, required hash key $key does not exist\n%s", (defined $fail_str) ? $fail_str : ""), "dnaorg", 1, $FH_HR); 
    }
    if(! defined $HR->{$key}) { 
      ofile_FAIL(sprintf("ERROR in $sub_name, required hash key $key exists but its value is undefined\n%s", (defined $fail_str) ? $fail_str : ""), "dnaorg", 1, $FH_HR); 
    }
  }

  return;
}

####################################################################
# the next line is critical, a perl module must return a true value
return 1;
####################################################################
