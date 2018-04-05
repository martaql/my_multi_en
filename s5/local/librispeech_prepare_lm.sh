#!/bin/bash

stage=-1

. ./cmd.sh
. ./path.sh

#lmtype=_libri
lmtype=$1
dict_dir=data/local/dict_nosp${lmtype} #_nosp_libri
lm_dir=data/local/lm/lm_libri
librispeech_data_dir=../../librispeech/s5/data

. utils/parse_options.sh


if [ $stage -le -1 ]; then
  rm -rf $lm_dir
  mkdir -p $lm_dir
  #Copy or download the LM resources
  #lm_url=www.openslr.org/resources/11
  #local/download_lm.sh $lm_url $lm_dir  
  lm_link=../../librispeech/s5/data/local/lm
  cp $lm_link/{4-gram.arpa.gz,lm_fglarge.arpa.gz} $lm_dir/
fi
 
if [ $stage -le 0 ]; then
  mkdir -p $dict_dir
  cp $librispeech_data_dir/local/dict_nosp/{extra_questions.txt,nonsilence_phones.txt,optional_silence.txt,silence_phones.txt,lexicon.txt} $dict_dir
fi

if [ $stage -le 1 ]; then
  # Prepare Lang using Librispeech dict
  utils/prepare_lang.sh --phone-symbol-table data/lang_nosp/phones.txt \
    $dict_dir "<UNK>" \
    data/local/tmp/lang_tmp${lmtype} \
    data/lang${lmtype}
fi

if [ $stage -le 2 ]; then
  #Format language models
  #local/librispeech_format_lms.sh --src-dir data/lang_${lmtype} $lm_dir/
  utils/build_const_arpa_lm.sh $lm_dir/lm_fglarge.arpa.gz data/lang${lmtype} data/lang${lmtype}_test_fglarge
fi

#exit 0
