#!/bin/bash

# Copyright 2016  Allen Guo
#           2017  Xiaohui Zhang
# Apache 2.0
#
# Modified: 2018 Marta

. ./cmd.sh
. ./path.sh

# paths to corpora (see below for example)
#ami=
librispeech=~/data/librispeech
#tedlium2=
wsj0=~/data/wsj/LDC/LDC93S6B
wsj1=~/data/wsj/LDC/LDC94S13B

set -e
# check for kaldi_lm
which get_word_map.pl > /dev/null
if [ $? -ne 0 ]; then
  echo "This recipe requires installation of tools/kaldi_lm. Please run extras/kaldi_lm.sh in tools/" && exit 1;
fi

# general options
stage=9
cleanup_stage=1
multi=multi_m  # This defines the "variant" we're using; see README.md
#srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
train_mono=false
train=false
decode=true

. utils/parse_options.sh

# Prepare corpora 
if [ $stage -le 0 ]; then
  mkdir -p data/local
  # librispeech
  local/librispeech_data_prep.sh $librispeech/LibriSpeech/train-clean-100 data/librispeech_100/train
  #local/librispeech_data_prep.sh $librispeech/LibriSpeech/train-clean-360 data/librispeech_360/train
  #local/librispeech_data_prep.sh $librispeech/LibriSpeech/train-other-500 data/librispeech_500/train
  local/librispeech_data_prep.sh $librispeech/LibriSpeech/test-clean data/librispeech/test
  # tedlium
  #local/tedlium_prepare_data.sh $tedlium2
  # wsj
  local/wsj_data_prep.sh $wsj0/??-{?,??}.? $wsj1/??-{?,??}.?
  local/wsj_format_data.sh
  utils/copy_data_dir.sh --spk_prefix wsj_ --utt_prefix wsj_ data/wsj/train_si284 data/wsj/train
  utils/copy_data_dir.sh --spk_prefix wsj_ --utt_prefix wsj_ data/wsj/test_eval92 data/wsj/test
  rm -r data/wsj/train_si284 2>/dev/null || true
  rm -r data/wsj/test_eval92 2>/dev/null || true
fi

# Normalize transcripts
if [ $stage -le 1 ]; then
  for f in data/*/{train,test}/text; do
  #for f in data/wsj/test/text; do
    echo Normalizing $f
    cp $f $f.orig
    local/normalize_transcript.py $f.orig > $f
  done
fi

# These commands(stages:2-4) build a dictionary containing the combination of
# many of the OOVs in the WSJ LM training (not yet:data and the Librispeech data),
# and trains an LM directly on that data 

# Prepare the basic dictionary (a combination of wsj+librispeech-CMU lexicons) in data/local/dict_combined.
# And prepare Language Model
if [ $stage -le 2 ]; then
  # We prepare the basic dictionary in data/local/dict_combined.
  local/prepare_dict_new_wsj_ls.sh $wsj1 $librispeech
fi

# We'll do multiple iterations of pron/sil-prob estimation. So the structure of
# the dict/lang dirs are designed as ${dict/lang_root}_${dict_affix}, where dict_affix
# is "nosp" or the name of the acoustic model we use to estimate pron/sil-probs.
dict_root=data/local/dict
lang_root=data/lang

# Setup dict and lang -nosp directories
dict_dir=${dict_root}_nosp
lang_dir=${lang_root}_nosp

if [ $stage -le 3 ]; then
  # Copy necessary phone files to dict directories
  mkdir -p $dict_dir
  rm $dict_dir/lexiconp.txt 2>/dev/null || true
  cp data/local/dict_combined/{lexicon,extra_questions,nonsilence_phones,silence_phones,optional_silence}.txt $dict_dir
  cp data/local/dict_combined/cleaned.gz $dict_dir

  # prepare (and validate) lang directory
  utils/prepare_lang.sh $dict_dir "<UNK>" data/local/tmp/lang_nosp $lang_dir

  echo 'End of stage 3'
fi

if [ $stage -le 4 ]; then
  # Setup LM directory
  lm_dir=data/local/lm
  mkdir -p $lm_dir

  # build LM and prepare test lang directories
  local/wsj_train_lms.sh $lm_dir $dict_dir
  local/wsj_format_local_lms.sh $lm_dir $lang_dir

  echo 'End of stage 4'
fi

#exit 0

# prepare LM and test lang directory
if [ $stage -le -24 ]; then
  mkdir -p data/local/lm
  cat data/{wsj,librispeech_*}/train/text > data/local/lm/text
  local/train_lms.sh  # creates data/local/lm/3gram-mincount/lm_unpruned.gz
  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    ${lang_root}_nosp data/local/lm/3gram-mincount/lm_unpruned.gz \
    ${dict_root}_nosp/lexicon.txt ${lang_root}_nosp_test_tg
fi

# prepare training data for experiments
if [ $stage -le 5 ]; then
  corpora="wsj librispeech_100" #librispeech_360 librispeech_500 wsj" #tedlium"

  # make training features
  mfccdir=mfcc
  for c in $corpora; do
    data=data/$c/train
    steps/make_mfcc.sh --mfcc-config conf/mfcc.conf \
      --cmd "$train_cmd" --nj 10 \
      $data exp/make_mfcc/$c/train || exit 1;
    steps/compute_cmvn_stats.sh \
      $data exp/make_mfcc/$c/train || exit 1;
  done

  # get rid of spk2gender files because not all corpora have them
  #rm data/*/train/spk2gender 2>/dev/null || true

  # create reco2channel_and_file files for wsj and librispeech
  #for c in $corpora; do
  #  awk '{print $1, $1, "A"}' data/$c/train/wav.scp > data/$c/train/reco2file_and_channel;
  #done

  # fix and validate training data directories
  # apply standard fixes, then validate
  for c in $corpora; do
    utils/fix_data_dir.sh data/$c/train
    utils/validate_data_dir.sh data/$c/train
  done

  echo 'End of stage 5'
fi

# prepare test data for experiments
if [ $stage -le 6 ]; then
  corpora="wsj librispeech"

  # make test features
  mfccdir=mfcc
  for c in $corpora; do
    data=data/$c/test
    steps/make_mfcc.sh --mfcc-config conf/mfcc.conf \
      --cmd "$train_cmd" --nj 10 \
      $data exp/make_mfcc/$c/test || exit 1;
    steps/compute_cmvn_stats.sh \
      $data exp/make_mfcc/$c/test || exit 1;
  done

  # fix and validate test data directories
  for c in $corpora; do
    utils/fix_data_dir.sh data/$c/test
    utils/validate_data_dir.sh data/$c/test
  done

  echo 'End of stage 6'
fi

if [ $stage -le 7 ]; then
  # Make small subsets of wsj data for early stage training.
  # 1 Make subset of wsj train data (=train_si284)
  # 2 Make subset with the shortest 2k utterances from si-84.
  # 3 Make subset with half of the data from si-84.
  utils/subset_data_dir.sh --first data/wsj/train 7138 data/wsj/train_si84 || exit 1;
  utils/subset_data_dir.sh --shortest data/wsj/train_si84 2000 data/wsj/train_si84_2kshort || exit 1;
  utils/subset_data_dir.sh data/wsj/train_si84 3500 data/wsj/train_si84_half || exit 1;
  # Remove duplicates: not sure if necessary??
  #utils/data/remove_dup_utts.sh 10 data/wsj/train_si84 data/wsj/train_si84_nodup

  # Make some small data subsets for early system-build stages.  Note, there are 29k
  # utterances in the train_clean_100 directory which has 100 hours of data.
  # For the monophone stages we select the shortest utterances, which should make it
  # easier to align the data from a flat start
  utils/subset_data_dir.sh --shortest data/librispeech_100/train 2000 data/librispeech_100/train_2kshort
  utils/subset_data_dir.sh data/librispeech_100/train 5000 data/librispeech_100/train_5k
  utils/subset_data_dir.sh data/librispeech_100/train 10000 data/librispeech_100/train_10k

  echo 'End of stage 7'
fi

# (original) train mono on wsj 10k short (nodup)
# train mono on si84_2kshort (first and last monophone pass)
if [ $stage -le 8 ]; then
  data_train_wsj=data/wsj/train_si84_2kshort
  data_train_librispeech=data/librispeech_100/train_2kshort
  if $train_mono; then
    #local/make_partitions_wsj_etc.sh --multi $multi --stage 1 || exit 1;
    # Train with wsj data
    steps/train_mono.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
      $data_train_wsj ${lang_root}_nosp exp/$multi/mono_wsj || exit 1;
    # Train mono with librispeech data
    #steps/train_mono.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
    #  $data_train_librispeech ${lang_root}_nosp exp/$multi/mono_ls || exit 1;
  fi

  if $train; then
    # Train first trigram on librispeech data
    steps/align_si.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
      $data_train_librispeech ${lang_root}_nosp exp/$multi/mono_wsj exp/$multi/mono_ls_ali || exit 1;
    steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" 2000 10000 \
      $data_train_librispeech ${lang_root}_nosp exp/$multi/mono_ls_ali exp/$multi/tri0 || exit 1;
  fi

  echo 'End of stage 8'
fi

# (original) train tri1a and tri1b (first and second triphone passes) on wsj 30k (nodup)
# train tri1 on si84_half (1st triphone pass)
if [ $stage -le 9 ]; then
  data_train_wsj=data/wsj/train_si84_half
  data_train_librispeech=data/librispeech_100/train_5k
  if $train; then
    #local/make_partitions_wsj_etc.sh --multi $multi --stage 2 || exit 1;
    steps/align_si.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
      $data_train_wsj ${lang_root}_nosp exp/$multi/tri0 exp/$multi/tri0_ali || exit 1; 
   steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" 2000 10000 \
      $data_train_wsj ${lang_root}_nosp exp/$multi/tri0_ali exp/$multi/tri1a || exit 1;

   steps/align_si.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
      $data_train_librispeech ${lang_root}_nosp exp/$multi/tri1a exp/$multi/tri1a_ali || exit 1;
   steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" 2000 10000 \
      $data_train_librispeech ${lang_root}_nosp exp/$multi/tri1a_ali exp/$multi/tri1b || exit 1;
  fi

  # decode
  if $decode; then
    gmm=tri1b
    graph_dir=exp/$multi/$gmm/graph_tgpr
    utils/mkgraph.sh ${lang_root}_nosp_test_tgpr \
      exp/$multi/$gmm $graph_dir || exit 1;
    ## we adapt nj to number of speakers: nspk 
    for e in wsj librispeech; do
      nspk=$(wc -l <data/$e/test/spk2utt)
      steps/decode_fmllr.sh --nj $nspk --cmd "$decode_cmd" --config conf/decode.config \
        $graph_dir data/$e/test exp/$multi/$gmm/decode_tgpr_$e || exit 1;
    done
  fi
  echo 'End of stage 9'
fi


# (original) train tri2 (third triphone pass) on wsj 100k (nodup)
# train tri2 on train_si84 (2nd triphone pass)
if [ $stage -eq 10 ]; then
  data_train=data/wsj/train_si84
  #local/make_partitions_wsj_etc.sh --multi $multi --stage 3 || exit 1;
  steps/align_si.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
    $data_train ${lang_root}_nosp exp/$multi/tri1 exp/$multi/tri1_ali || exit 1;
  steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" 2500 15000 \
    $data_train ${lang_root}_nosp exp/$multi/tri1_ali exp/$multi/tri2 || exit 1;
  # copied from wsj original training
  #steps/train_lda_mllt.sh --cmd "$train_cmd" \
  #    --splice-opts "--left-context=3 --right-context=3" 2500 15000 \
  #    $data_train ${lang_root}_nosp exp/$multi/tri1_ali exp/$multi/tri2 || exit 1; 

  echo 'End of stage 10'
fi

# (original) train tri3a (4th triphone pass) on whole wsj
# train tri2 on train (=train_si284) (3rd triphone pass)
if [ $stage -eq 11 ]; then
  data_train=data/wsj/train
  #local/make_partitions_wsj_etc.sh --multi $multi --stage 4 || exit 1;
  steps/align_si.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
    $data_train ${lang_root}_nosp exp/$multi/tri2 exp/$multi/tri2_ali || exit 1;
  steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" 4200 40000 \
    $data_train ${lang_root}_nosp exp/$multi/tri2_ali exp/$multi/tri3a || exit 1;
  # copied from wsj original training
  #steps/train_sat.sh --cmd "$train_cmd" 4200 40000 \
  #  $data_train ${lang_root}_nosp exp/$multi/tri2_ali exp/$multi/tri3a || exit 1;

  # decode
  if $decode; then
    gmm=tri3a
    graph_dir=exp/$multi/$gmm/graph_tgpr
    utils/mkgraph.sh ${lang_root}_nosp_test_tgpr \
      exp/$multi/$gmm $graph_dir || exit 1;
    ## we adapt nj to number of speakers: nspk 
    for e in wsj librispeech; do
      nspk=$(wc -l <data/$e/test/spk2utt)
      steps/decode_fmllr.sh --nj $nspk --cmd "$decode_cmd" --config conf/decode.config $graph_dir \
        data/$e/test exp/$multi/$gmm/decode_tgpr_$e || exit 1;
    done
  fi
  echo 'End of stage 11'
fi

# train tri3b (LDA+MLLT) on whole librispeech + wsj (nodup)
if [ $stage -eq 12 ]; then
  #local/make_partitions_wsj_etc.sh --multi $multi --stage 5 || exit 1;
  steps/align_si.sh --boost-silence 1.25 --nj 100 --cmd "$train_cmd" \
    data/$multi/tri3a_ali ${lang_root}_nosp exp/$multi/tri3a exp/$multi/tri3a_ali || exit 1;
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" 11500 400000 \
    data/$multi/tri3b ${lang_root}_nosp exp/$multi/tri3a_ali exp/$multi/tri3b || exit 1;
  # decode
  if $decode; then
    gmm=tri3b
    graph_dir=exp/$multi/$gmm/graph_tgpr
    utils/mkgraph.sh ${lang_root}_nosp_test_tgpr \
      exp/$multi/$gmm $graph_dir || exit 1;
    for e in wsj librispeech; do
      ## we adapt nj to number of speakers: nspk 
      nspk=$(wc -l <data/$e/test/spk2utt)
      steps/decode_fmllr.sh --nj 25 --cmd "$decode_cmd" --config conf/decode.config $graph_dir \
        data/$e/test exp/$multi/$gmm/decode_tgpr_$e || exit 1;
    done
  fi
fi

# reestimate pron & sil-probs
dict_affix=${multi}_tri3b
if [ $stage -eq 13 ]; then
  gmm=tri3b
  steps/get_prons.sh --cmd "$train_cmd" data/$multi/$gmm ${lang_root}_nosp exp/$multi/$gmm
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
    ${dict_root}_nosp exp/$multi/$gmm/pron_counts_nowb.txt \
    exp/$multi/$gmm/sil_counts_nowb.txt exp/$multi/$gmm/pron_bigram_counts_nowb.txt ${dict_root}_${dict_affix}
  utils/prepare_lang.sh ${dict_root}_${dict_affix} "<unk>" data/local/lang_${dict_affix} ${lang_root}_${dict_affix}
  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    ${lang_root}_${dict_affix} data/local/lm/3gram-mincount/lm_unpruned.gz \
    ${dict_root}_${dict_affix}/lexicon.txt ${lang_root}_${dict_affix}_test_tgpr
  # decode
  if $decode; then
    gmm=tri3b
    graph_dir=exp/$multi/$gmm/graph_tgpr_sp
    utils/mkgraph.sh ${lang_root}_${dict_affix}_test_tgpr \
      exp/$multi/$gmm $graph_dir || exit 1;
    for e in wsj librispeech; do
      ## we adapt nj to number of speakers: nspk 
      nspk=$(wc -l <data/$e/test/spk2utt)
      steps/decode_fmllr.sh --nj $nspk --cmd "$decode_cmd" --config conf/decode.config $graph_dir \
        data/$e/test exp/$multi/$gmm/decode_tgpr_sp_$e || exit 1;
    done
  fi
fi

dict_affix=nosp
lang=${lang_root}_${dict_affix}
if [ $stage -eq 14 ]; then
  # This does the actual data cleanup.
  steps/cleanup/clean_and_segment_data.sh --stage $cleanup_stage --nj 100 --cmd "$train_cmd" \
  data/tedlium/train $lang exp/$multi/tri3b exp/$multi/tri3b_tedlium_cleaning_work data/$multi/tedlium_cleaned/train
fi

exit 0

