# =============================================================================
# config.mk – Pipeline Configuration for Ficus aurea
# Edit these variables before running `make`
# =============================================================================

# ── Input ──────────────────────────────────────────────────────────────────────
GENOME       := ficus_aurea.fasta
GENOME_NAME  := Ficus_aurea

# AUGUSTUS species model – vitis_vinifera is a well-trained woody eudicot model
SPECIES_NAME := vitis_vinifera

# ── Compute ────────────────────────────────────────────────────────────────────
THREADS := 16

# ── Conda environments ─────────────────────────────────────────────────────────
# Environment containing BUSCO, RepeatModeler, and RepeatMasker
CONDA_ANNOTATION := genome_annot

# Environment containing Apptainer (for running the BRAKER3 .sif) and AGAT
CONDA_APPTAINER  := genome_annot

# Environment containing STAR and samtools (only needed if using RNA-seq)
CONDA_RNASEQ     := rnaseq

# ── BUSCO ──────────────────────────────────────────────────────────────────────
BUSCO_LINEAGE    := eudicots_odb10
BUSCO_DOWNLOADS  := busco_downloads
BUSCO_EXTRA_ARGS :=
BUSCO_RAW_DIR    := 01_busco_raw
BUSCO_MASKED_DIR := 04_busco_masked

# ── RepeatModeler ──────────────────────────────────────────────────────────────
REPEAT_MODELER_DIR := 02_repeatmodeler
REPEAT_ENGINE      := ncbi

# ── RepeatMasker ──────────────────────────────────────────────────────────────
REPEAT_MASKER_DIR := 03_repeatmasker

# (Optional) curated plant TE library to merge with the de novo library.
# Leave blank to use the RepeatModeler library alone.
REPEAT_EXTRA_LIB :=

# ── RNA-seq (optional – needed for ET or ETP mode) ────────────────────────────
# BRAKER3 mode is determined automatically by what you set below:
#
#   PROTEIN_DB only              → EP  mode (proteins only)       ← current
#   RNA_R1 / RNA_BAM only        → ET  mode (RNA-seq only)
#   PROTEIN_DB + RNA_R1/RNA_BAM  → ETP mode (proteins + RNA-seq)  ← best
#
# Option A – raw FASTQ (pipeline will run STAR alignment for you):
#   RNA_R1 := sample_R1.fastq.gz
#   RNA_R2 := sample_R2.fastq.gz   # omit for single-end
#
# Option B – pre-aligned sorted BAM (skips STAR steps entirely):
#   RNA_BAM := aligned_sorted.bam
#
# Leave both commented out to run EP mode (proteins only).
# RNA_R1  :=
# RNA_R2  :=
# RNA_BAM :=

STAR_DIR := 05_star

# ── Apptainer / BRAKER3 ────────────────────────────────────────────────────────
# Path to your BRAKER3 .sif file.
# Build:   make build_sif
# Or point at an existing image, e.g.:
#   BRAKER3_SIF := /scratch/shared/containers/braker3.sif
BRAKER3_SIF := braker3.sif

# ── BRAKER3 evidence ───────────────────────────────────────────────────────────
BRAKER_DIR := 06_braker

# Protein database (EP or ETP mode).
# Download OrthoDB Viridiplantae: (change to your desired lineage if needed)
#   wget https://bioinf.uni-greifswald.de/bioinf/partitioned_odb12/Viridiplantae.fa.gz
#   gunzip Viridiplantae.fa.gz
# Comment out to run ET mode (RNA-seq only).
PROTEIN_DB := Viridiplantae.fa

# Extra BRAKER3 arguments.
# --AUGUSTUS_ab_initio outputs raw ab initio predictions alongside evidence-
# based models – useful for QC. Mode flags (--epmode / --etpmode) are set
# automatically by the Makefile based on what evidence you provide.
BRAKER_EXTRA_ARGS := --AUGUSTUS_ab_initio
