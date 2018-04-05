#!/bin/bash

# Copyright Johns Hopkins University (Author: Daniel Povey) 2012
#           Guoguo Chen 2014
#
# Modified: 2018 Marta


echo "$0 $@"  # Print the command line for logging
. ./path.sh
#. utils/parse_options.sh || exit 1;

lm_dir=$1	#data/local/lm
lang_dir=$2	#data/local/lang_nosp

[ ! -d $lang_dir ] &&\
  echo "Expect $lang_dir to exist" && exit 1;

lm_srcdir_3g=$lm_dir/3gram-mincount
#lm_srcdir_4g=$lm_dir/4gram-mincount

[ ! -d "$lm_srcdir_3g" ] && echo "No such dir $lm_srcdir_3g" && exit 1;
#[ ! -d "$lm_srcdir_4g" ] && echo "No such dir $lm_srcdir_4g" && exit 1;

for d in ${lang_dir}_test_{tg,tgpr,tgconst}; do #,fg,fgpr,fgconst}; do
  rm -r $d 2>/dev/null
  cp -r $lang_dir $d
done

#lang=data/lang${lang_suffix}_bd

# Check a few files that we have to use.
for f in words.txt oov.int; do
  if [[ ! -f $lang_dir/$f ]]; then
    echo "$0: no such file $lang_dir/$f"
    exit 1;
  fi
done

# Parameters needed for ConstArpaLm.
unk=`cat $lang_dir/oov.int`
bos=`grep "<s>" $lang_dir/words.txt | awk '{print $2}'`
eos=`grep "</s>" $lang_dir/words.txt | awk '{print $2}'`
if [[ -z $bos || -z $eos ]]; then
  echo "$0: <s> and </s> symbols are not in $lang_dir/words.txt"
  exit 1;
fi

# Be careful: this time we dispense with the grep -v '<s> <s>' so this might
# not work for LMs generated from all toolkits.

## Build 3gram Grammar
gunzip -c $lm_srcdir_3g/lm_pr6.0.gz | \
  arpa2fst --disambig-symbol=#0 \
           --read-symbol-table=$lang_dir/words.txt - ${lang_dir}_test_tgpr/G.fst || exit 1;
  fstisstochastic ${lang_dir}_test_tgpr/G.fst

gunzip -c $lm_srcdir_3g/lm_unpruned.gz | \
  arpa2fst --disambig-symbol=#0 \
           --read-symbol-table=$lang_dir/words.txt - ${lang_dir}_test_tg/G.fst || exit 1;
  fstisstochastic ${lang_dir}_test_tg/G.fst

# Build ConstArpaLm for the unpruned language model.
gunzip -c $lm_srcdir_3g/lm_unpruned.gz | \
  utils/map_arpa_lm.pl $lang_dir/words.txt | \
  arpa-to-const-arpa --bos-symbol=$bos --eos-symbol=$eos \
  --unk-symbol=$unk - ${lang_dir}_test_tgconst/G.carpa || exit 1

exit 0;
## Leaving out 4gram for now

## Build 4gram Grammar
gunzip -c $lm_srcdir_4g/lm_unpruned.gz | \
  arpa2fst --disambig-symbol=#0 \
           --read-symbol-table=$lang_dir/words.txt - ${lang_dir}_test_fg/G.fst || exit 1;
  fstisstochastic ${lang_dir}_test_fg/G.fst

# Build ConstArpaLm for the unpruned language model.
gunzip -c $lm_srcdir_4g/lm_unpruned.gz | \
  utils/map_arpa_lm.pl $lang_dir/words.txt | \
  arpa-to-const-arpa --bos-symbol=$bos --eos-symbol=$eos \
  --unk-symbol=$unk - ${lang_dir}_test_fgconst/G.carpa || exit 1

gunzip -c $lm_srcdir_4g/lm_pr7.0.gz | \
  arpa2fst --disambig-symbol=#0 \
           --read-symbol-table=$lang/words.txt - ${lang_dir}_test_fgpr/G.fst || exit 1;
  fstisstochastic ${lang_dir}_test_fgpr/G.fst

#exit 0;
