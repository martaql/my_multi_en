#!/bin/bash

stage=4
substage=0
#home_dir=pwd

. ./cmd.sh

. ./path.sh

if [ $stage -eq 0 ]; then
  mkdir -p data
  mkdir -p data/local
  mkdir -p data/local/lm
  mkdir -p data/local/tmp
fi

dict_root=data/local/dict
lang_root=data/lang
lm_root=data/local/lm
tmp_dir=data/local/tmp

if [ $stage -eq 1 ]; then
	
  lmtype=wsj
  dict_dir=${dict_root}_${lmtype}
  lang_dir=${lang_root}_${lmtype}
  lm_dir=${lm_root}/lm_${lmtype}
  librispeech_data_dir=../../librispeech/s5/data
  
  if [ $substage -le 0 ]; then
    rm -rf $tmp_dir/*$lmtype*
    rm -rf $lm_dir
    mkdir -p $lm_dir
    echo "End of substage 0"
  fi
  
  if [ $substage -le 1 ]; then
    #Copy phone-files from wsj and librispeech data-dir
    #wsj_data_dir=../s5/data
    rm -rf mkdir ${dict_dir}
    rm -rf mkdir ${dict_dir}_larger
    mkdir ${dict_dir}
    mkdir ${dict_dir}_larger
    #cp $wsj_data_dir/local/dict_nosp/
    cp $libirspeech_data_dir/local/dict_nosp/{extra_questions,nonsilence_phones,optional_silence,silence_phones}.txt \
      ${dict_dir}
    #cp $wsj_data_dir/local/dict_nosp_larger/
    #cp data/local/dict_libri/{extra_questions,nonsilence_phones,optional_silence,silence_phones,lexicon} \
    #  ${dict_dir}_larger
    #cp $wsj_data_dir/local/dict_nosp_larger/cleaned.gz ${dict_dir}_larger
    echo "End of substage 1"
  fi

  if [ $substage -le 2 ]; then

    local/wsj_prepare_dict.sh --dict-suffix "_$lmtype"

    utils/prepare_lang.sh --phone-symbol-table $libirspeech_data_dir/lang_nosp/phones.txt \
    ${dict_dir} "<UNK>" \
    $tmp_dir/lang_tmp_${lmtype} ${lang_dir}

    wsj1=~/data/wsj/LDC/LDC94S13B
    local/wsj_extend_dict.sh --dict-suffix _$lmtype $wsj1/13-32.1

    # Prepare Language
    utils/prepare_lang.sh \
      --phone-symbol-table $libirspeech_data_dir/lang_nosp/phones.txt \
      ${dict_dir}_larger "<UNK>" \
      $tmp_dir/lang_tmp_${lmtype}_larger ${lang_dir}_bd	
    
    # Train language models
    local/wsj_train_lms.sh --dict-suffix "_${lmtype}" $lm_dir
    
    # Format language Models
    local/wsj_format_local_lms.sh --lang-suffix "_${lmtype}" $lm_dir	
    
    echo "End of substage 1"
  fi
    
  echo "End of stage 1"
fi

#exit 0

if [ $stage -eq 2 ]; then     
    
  lmtype=libri
  dict_dir=${dict_root}_${lmtype}
  lang_dir=${lang_root}_${lmtype}
  lm_dir=${lm_root}/lm_${lmtype}  
    
  if [ $substage -eq 0 ]; then
    rm -rf $tmp_dir/*$lmtype*
    rm -rf $lm_dir
    mkdir -p $lm_dir
    #Copy or download the LM resources
    #lm_url=www.openslr.org/resources/11
    #local/librispeech_download_lm.sh $lm_url $lm_dir  
    lm_link=../../librispeech/s5/data/local/lm
    cp $lm_link/* $lm_dir/
    echo "End of substage 0"
  fi

  if [ $substage -eq 1 ]; then
    #Copy phone-files from librispeech data-dir
    librispeech_data_dir=../../librispeech/s5/data
    rm -rf mkdir ${dict_dir}
    mkdir ${dict_dir}
    cp $librispeech_data_dir/local/dict_nosp/{extra_questions,nonsilence_phones,optional_silence,silence_phones,lexicon}.txt \
      ${dict_dir}
    echo "End of substage 1"
  fi

  if [ $substage -le 2 ]; then	  
    # Prepare Lang using wsj dict
    #utils/prepare_lang.sh \
    #  --phone-symbol-table ../s5/data/lang_nosp/phones.txt \
    #  ${dict_dir}_wsj_larger "<UNK>" \
    #  $tmp_dir/lang_tmp_${lmtype} ${lang_dir}_${lmtype}
    
    # Prepare Lang using Librispeech dict
    utils/prepare_lang.sh \
      --phone-symbol-table ../s5/data/lang_nosp/phones.txt \
      ${dict_dir} "<UNK>" \
      $tmp_dir/lang_tmp_${lmtype} ${lang_dir}
    
    
    #Format language models
    local/librispeech_format_lms.sh --src-dir ${lang_dir} $lm_dir
    
    #Create ConstArpaLm format language model for full 3-gram and 4-gram LMs
    utils/build_const_arpa_lm.sh $lm_dir/lm_tglarge.arpa.gz ${lang_dir} ${lang_dir}_test_tglarge
    utils/build_const_arpa_lm.sh $lm_dir/lm_fglarge.arpa.gz ${lang_dir} ${lang_dir}_test_fglarge
    
    echo "End of substage 2"
  fi
    
  echo "End of stage 2"
fi

#exit 0

if [ $stage -eq 3 ]; then  
  #################################################
  #langdir=data/lang_wsj_test_bd_tgpr
  #langdir=data/lang_librispeech_test_tgsmall
  #################################################
  #modeldir=../s5/exp/tri3b_sat
  #################################################
  #outputdir=models/tri3b_sat_wsj_test_bd_tgpr
  #outputdir=models/tri3b_sat_librispeech_test_tgsmall
  #################################################
  mkdir -p exp

  for lmtype in wsj; do # wsj libri; do

    if [ $lmtype = 'libri' ]; then
      modeltype=wsj_tri3b_sat
      model_dir=../s5/exp/multi_m/tri3b_sat
      output_dir=exp/${modeltype}_$lmtype   
    fi

    if [ $lmtype = 'wsj' ]; then
      modeltype=libri_tri4b
      model_dir=../../librispeech/s5/exp/tri4b
      output_dir=exp/${modeltype}_$lmtype
    fi

    #rm -rf $output_dir
    mkdir -p $output_dir

    model=$model_dir/final.mdl
    tree=$model_dir/tree
    cp $model $tree $output_dir    

    for optsfile in splice_opts cmvn_opts delta_opts; do
      if [ -e $model_dir/$optsfile ]; then
        cp $model_dir/$optsfile $output_dir
      fi
    done

    for file_end in mat alimdl nnet feature_transform ; do
      if [ -e $model_dir/final.$file_end ]; then
        cp $model_dir/final.$file_end $output_dir
      fi
    done
    
    for file in prior_counts ali_train_pdf.counts ; do
      if [ -e $model_dir/$file ]; then
        cp $model_dir/$file $output_dir
      fi
    done
  done
  
  echo "End of stage 3"
fi

#exit 0

if [ $stage -eq 4 ]; then

  for lmtype in wsj; do # wsj libri; do

    if [ $lmtype = 'libri' ]; then
      model=wsj_tri3b_sat
      model_dir=exp/${model}_$lmtype
      utils/mkgraph.sh data/lang_${lmtype}_test_tgsmall $model_dir \
        $model_dir/graph_${lmtype}_tgsmall
      steps/decode_fmllr.sh --nj 20 --cmd "$decode_cmd" \
        $model_dir/graph_${lmtype}_tgsmall data/$lmtype/test  \
        $model_dir/decode_${lmtype}_tgsmall
      steps/lmrescore.sh --cmd "$decode_cmd" data/lang_${lmtype}_test_{tgsmall,tgmed} \
        data/$lmtype/test  $model_dir/decode_${lmtype}_{tgsmall,tgmed}
      steps/lmrescore_const_arpa.sh
        --cmd "$decode_cmd" data/lang_${lmtype}_test_{tgsmall,tglarge} \
        data/$lmtype/test  $model_dir/decode_${lmtype}_{tgsmall,tglarge}
      steps/lmrescore_const_arpa.sh \
        --cmd "$decode_cmd" data/lang_${lmtype}_test_{tgsmall,fglarge} \
        data/$lmtype/test  $model_dir/decode_${lmtype}_{tgsmall,fglarge}
    fi

    if [ $lmtype = 'wsj' ]; then
      model=libri_tri4b
      model_dir=exp/${model}_$lmtype
      utils/mkgraph.sh data/lang_${lmtype}_test_bd_tgpr $model_dir \
        $model_dir/graph_${lmtype}_bd_tgpr
      steps/decode_fmllr.sh --cmd "$decode_cmd" --nj 8  \
        $model_dir/graph_${lmtype}_bd_tgpr \
        data/$lmtype/test $model_dir/decode_${lmtype}_bd_tgpr
       steps/lmrescore.sh --cmd "$decode_cmd" \
        data/lang_${lmtype}_test_tgpr data/lang_${lmtype}_test_bd_tg \
        data/$lmtype/test exp/tri3b/decode_${lmtype}_bd_{tgpr,tg}
    fi

  done

  echo "End of stage 4"
fi

#exit 0

if [ $stage -le 6 ]; then
  # getting results (see RESULTS file)
  for lmtype in libri wsj; do
    echo "=== test set $lmtype ===" ;
    for x in exp/tri*/decode_${lmtype}_*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done ;
  done > RESULTS_marta
  echo "End of stage 6"
fi

#exit 0
