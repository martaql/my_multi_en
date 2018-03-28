#!/bin/bash

# This script first prepares librispeech lexicon and CMU + tedlium combined lexicon (refered as tedlium later on for simplicity).
# Then it merges the two lexicons to produce the final lexicon data/local/dict_combined.
# After phone mapping, all alternative pronunciations lexicon are included??? Maybe???



. ./cmd.sh
. ./path.sh

stage=1

#check existing directories
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: prepare_dict.sh /path/to/LIBRISPEECH [/path/to/TEDLIUM_r2]"
  exit 1; 
fi 

LIBRISPEECH_DIR=$1
TEDLIUM_DIR=$2

# This function filters lines that are common in both files
function filter_common {
    awk 'NR==FNR{arr[$0]++;next} arr[$0] {print}' $1 $2
}

# This function filters lines in file2 that are not in file1
function filter_different {
    awk 'NR==FNR{arr[$0]++;next} !arr[$0] {print}' $1 $2
}

dir=data/local/dict_combined
librispeech_dir=data/local/dict_librispeech
tedlium_dir=data/local/dict_tedlium

if [ $stage -le 0 ]; then 
  # Prepare switchboard lexicon
  local/librispeech_prepare_dict.sh --stage 3 ##check

  # Prepare cmudict + tedlium lexicon
  local/cmu_tedlium_prepare_dict.sh $TEDLIUM_DIR

  cmu_tedlium_dir=data/local/dict_cmu_tedlium
  mkdir -p $tedlium_dir
  for lex in {silence_phones.txt,optional_silence.txt,nonsilence_phones.txt,extra_questions.txt,lexicon.txt}; do
   cat ${cmu_tedlium_dir}/$lex | perl -pe 'y/[a-z]/[A-Z]/' >${tedlium_dir}/$lex
  done
  rm -rf $cmu_tedlium_dir
fi

if [ $stage -le 1 ]; then
  rm -rf $dir && mkdir -p $dir

  # Find words that are unique to librispeech lexicon (excluding non-scored words)
  utils/filter_scp.pl --exclude ${tedlium_dir}/lexicon.txt \
    ${librispeech_dir}/lexicon.txt | grep -v '\[*\]' | grep -v '<unk>'  > ${dir}/lexicon_librispeech_unique.txt || exit 1;

  # Find words that exist in both librispeech and tedlium lexicons (excluding non-scored words)
  utils/filter_scp.pl --exclude ${dir}/lexicon_librispeech_unique.txt \
    ${librispeech_dir}/lexicon.txt | grep -v '\[*\]' | grep -v '<unk>' > ${dir}/lexicon_librispeech1.txt || exit 1;

  # Find words that have same pronounciation in both dictionaries - common lines
  filter_common ${tedlium_dir}/lexicon.txt \
    ${dir}/lexicon_librispeech1.txt > ${dir}/lexicon_re_match_pron.txt || exit 1;

  # Find words in librispeech lexicon that have different pronounciation from tedlium - different lines
  filter_different ${dir}/lexicon_re_match_pron.txt \
    ${dir}/lexicon_librispeech1.txt > ${dir}/lexicon_librispeech2.txt || exit 1;

  # lexicon_re_librispeech3.txt contains lines that match after phone mapping
  filter_common ${tedlium_dir}/lexicon.txt \
    ${dir}/lexicon_librispeech2.txt > ${dir}/lexicon_re_librispeech3.txt || exit 1;

  # lexicon_librispeech3.txt contains lines that do not match after phone mapping (alternative pronunciations).
  filter_different ${tedlium_dir}/lexicon.txt \
    ${dir}/lexicon_librispeech2.txt > ${dir}/lexicon_librispeech3.txt || exit 1;

  # Extract lines from tedlium that have the above words
  utils/filter_scp.pl ${dir}/lexicon_librispeech3.txt ${tedlium_dir}/lexicon.txt > ${dir}/lexicon_tedlium4.txt || exit 1;

  # Writing to lexicon.txt
  cat ${dir}/lexicon_librispeech3.txt ${dir}/lexicon_librispeech_unique.txt ${tedlium_dir}/lexicon.txt | sort -u > ${dir}/lexicon.txt

  # Separate the lexicon word and phoneme expansion by TAB
  cat ${dir}/lexicon.txt | awk '{printf("%s\t",$1); for(i=2;i<NF;i++) {printf("%s ",$i);} printf("%s\n",$NF)}' > ${dir}/lexicon_tab_separated.txt
  mv ${dir}/lexicon_tab_separated.txt ${dir}/lexicon.txt

  # copy silence, nonsilence and optional silence phones from librispeech dict
  #cp ${librispeech_dir}/{nonsilence_phones.txt,silence_phones.txt,optional_silence.txt,extra_questions.txt} ${dir}
  cp ${librispeech_dir}/{nonsilence_phones.txt,optional_silence.txt,extra_questions.txt} ${dir}
  #cp ${librispeech_dir}/{nonsilence_phones.txt,optional_silence.txt} ${dir}

  # combine silence_phones.txt, optional_silence.txt and extra questions of both dict
  sort -u ${librispeech_dir}/silence_phones.txt ${tedlium_dir}/silence_phones.txt >${dir}/silence_phones.txt
  #paste ${librispeech_dir}/extra_questions.txt ${tedlium_dir}/extra_questions.txt >extra_questions.txt
  #sed -n 1p ${librispeech_dir}/extra_questions.txt | sed 's/$/LAUGHTER NOISE OOV /' >${dir}/extra_questions.txt
  #sed -n '2$p' ${librispeech_dir}/extra_questions.txt >>${dir}/extra_questions.txt
fi

if [ $stage -le 2 ]; then
  # validate the dict directory
  utils/validate_dict_dir.pl $dir
fi


echo "End of prepare_combined_dict"
