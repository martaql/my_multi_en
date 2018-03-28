#!/bin/bash

# Copyright 2017  Intellisist, Inc. (Author: Navneeth K)
#           2017  Xiaohui Zhang
# Apache License 2.0
#
# Modified: 2018 Marta

# This script first prepares wsj lexicon and librispeech lexicon.
# Then it merges the two lexicons to produce the final lexicon data/local/dict_combined.
# After phone mapping, all alternative pronunciations lexicon are included??? Maybe???

. ./cmd.sh
. ./path.sh

stage=2

#check existing directories
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: prepare_dict.sh /path/to/WSJ [/path/to/LIBRISPEECH]"
  exit 1; 
fi 

# Original Data Paths
WSJ1_DIR=$1
LIBRISPEECH_DIR=$2
#TEDLIUM_DIR=$2

# This function filters lines that are common in both files
function filter_common {
    awk 'NR==FNR{arr[$0]++;next} arr[$0] {print}' $1 $2
}

# This function filters lines in file2 that are not in file1
function filter_different {
    awk 'NR==FNR{arr[$0]++;next} !arr[$0] {print}' $1 $2
}

# New Local Data Paths
dir=data/local/dict_combined
wsj_dir0=data/local/dict_wsj
wsj_dir=data/local/dict_wsj_larger
#librispeech_dir=data/local/dict_librispeech

if [ $stage -eq -2 ]; then
  rm -rf $librispeech_dir && mkdir -p $librispeech_dir
  #Prepare Librispeech lexicon
  local/librispeech_prepare_dict.sh --stage 3 ##check
fi

if [ $stage -eq -1 ]; then
  rm -rf $wsj_dir0 && mkdir -p $wsj_dir0
  # Prepare wsj lexicon
  local/wsj_prepare_dict.sh $wsj_dir0
fi

if [ $stage -eq 0 ]; then
  rm -rf $wsj_dir && mkdir -p $wsj_dir
  # Prepare wsj extended lexicon
  local/wsj_extend_dict.sh $wsj_dir0 $WSJ1_DIR/13-32.1
fi

if [ $stage -le 1 ]; then
  #dir=data/local/dict_combined
  rm -rf $dir && mkdir -p $dir
  
  # copy silence, nonsilence and optional silence phones from wsj dict
  cp ${wsj_dir}/{cleaned.gz,nonsilence_phones.txt,silence_phones.txt,optional_silence.txt,extra_questions.txt,lexicon.txt} ${dir}
fi

if [ $stage -eq -20 ]; then
  #dir=data/local/dict_combined
  rm -rf $dir && mkdir -p $dir
  
  # Find words that are unique to wsj lexicon (excluding non-scored words)
  utils/filter_scp.pl --exclude ${librispeech_dir}/lexicon.txt \
  ${wsj_dir}/lexicon.txt | grep -v '\[*\]' | grep -v '<unk>'  > ${dir}/lexicon_wsj_unique.txt || exit 1;
  
  # Find words that exist in both wsj and librispeech lexicons (excluding non-scored words)
  utils/filter_scp.pl --exclude ${dir}/lexicon_wsj_unique.txt \
  ${wsj_dir}/lexicon.txt | grep -v '\[*\]' | grep -v '<unk>' > ${dir}/lexicon_wsj1.txt || exit 1;
  
  # Find words that have same pronounciation in both dictionaries - common lines
  filter_common ${librispeech_dir}/lexicon.txt \
  ${dir}/lexicon_wsj1.txt > ${dir}/lexicon_re_match_pron.txt || exit 1;
  
  # Find words in wsj lexicon that have different pronounciation from librispeech - different lines
  filter_different ${dir}/lexicon_re_match_pron.txt \
  ${dir}/lexicon_wsj1.txt > ${dir}/lexicon_wsj2.txt || exit 1;
  
  # lexicon_re_wsj4.txt contains lines that match after phone mapping
  filter_common ${librispeech_dir}/lexicon.txt \
  ${dir}/lexicon_wsj2.txt > ${dir}/lexicon_re_wsj3.txt || exit 1;
  
  # lexicon_wsj3.txt contains lines that do not match after phone mapping (alternative pronunciations).
  filter_different ${librispeech_dir}/lexicon.txt \
  ${dir}/lexicon_wsj2.txt > ${dir}/lexicon_wsj3.txt || exit 1;
  
  # Extract lines from librispeech that have the above words
  utils/filter_scp.pl ${dir}/lexicon_wsj3.txt ${librispeech_dir}/lexicon.txt > ${dir}/lexicon_librispeech3.txt || exit 1;
  
  # Writing to lexicon.txt
  cat ${dir}/lexicon_wsj3.txt ${dir}/lexicon_wsj_unique.txt ${librispeech_dir}/lexicon.txt | sort -u > ${dir}/lexicon.txt
  
  # Separate the lexicon word and phoneme expansion by TAB
  cat ${dir}/lexicon.txt | awk '{printf("%s\t",$1); for(i=2;i<NF;i++) {printf("%s ",$i);} printf("%s\n",$NF)}' > ${dir}/lexicon_tab_separated.txt
  mv ${dir}/lexicon_tab_separated.txt ${dir}/lexicon.txt
  
  # copy silence, nonsilence and optional silence phones from wsj dict
  cp ${wsj_dir}/{nonsilence_phones.txt,silence_phones.txt,optional_silence.txt,extra_questions.txt} ${dir}
fi

if [ $stage -le 2 ]; then
  # validate the dict directory
  utils/validate_dict_dir.pl $dir
fi
