# Genome Annotation Pipeline

A reproducible `make`-based pipeline for de novo genome annotation of an unmasked assembly.

```
Raw Assembly
    │
    ├──▶ [BUSCO]           Completeness check on raw assembly
    │
    ├──▶ [RepeatModeler]   Build de novo TE/repeat library
    │
    ├──▶ [RepeatMasker]    Soft-mask genome with repeat library
    │
    ├──▶ [BUSCO]           Completeness check on masked assembly
    │
    └──▶ [BRAKER3]         Evidence-based gene annotation
```

---

## Dependencies

Install all tools and ensure they are on your `$PATH`.

| Tool | Version | Purpose | Install |
|---|---|---|---|
| [BUSCO](https://busco.ezlab.org/) | ≥5.x | Assembly completeness | `conda install -c bioconda busco` |
| [RepeatModeler](https://www.repeatmasker.org/RepeatModeler/) | ≥2.0 | De novo repeat/TE library | `conda install -c bioconda repeatmodeler` |
| [RepeatMasker](https://www.repeatmasker.org/) | ≥4.1 | Soft-mask genome | `conda install -c bioconda repeatmasker` |
| [BRAKER3](https://github.com/Gaius-Augustus/BRAKER) | ≥3.x | Gene annotation | See BRAKER3 docs |
| [AUGUSTUS](https://github.com/Gaius-Augustus/Augustus) | ≥3.5 | Ab initio gene models | Required by BRAKER |
| [GeneMark-ETP](http://topaz.gatech.edu/GeneMark/) | latest | Gene models (license required) | See GeneMark docs |
| [AGAT](https://github.com/NBISweden/AGAT) | any | GTF→GFF3 conversion | `conda install -c bioconda agat` |

### Conda environment (recommended)

```bash
conda create -n genome_annot -c bioconda -c conda-forge \
    busco repeatmodeler repeatmasker agat apptainer
conda activate genome_annot

conda create -n rnaseq -c bioconda \
    star samtools 
```

### Download Braker3 image 

```bash
#download image
wget https://hub.docker.com/r/teambraker/braker3

# build image
singularity build braker3.sif docker://teambraker/braker3:latest
```

---

## Quick Start

### 1. Edit `config.mk`

```makefile
GENOME       := /path/to/your/assembly.fasta
GENOME_NAME  := MySpecies
SPECIES_NAME := MySpecies_v1
THREADS      := 32
BUSCO_LINEAGE := embryophyta_odb10   # change to your clade

# Evidence for BRAKER (use one or both):
PROTEIN_DB   := orthodb_proteins.fa

```

### 2. Run the pipeline

```bash
# Full pipeline
make all

# Or step-by-step
make busco
make repeat_modeler
make repeat_masker
make busco_masked
make braker
```

### 3. Dry-run (see commands without running)

```bash
make -n all
```

---

## Output Structure

```
01_busco_raw/               BUSCO results on raw assembly
02_repeatmodeler/           RepeatModeler database + de novo repeat library
    ├── MySpecies-families.fa       ← de novo repeat library
    └── MySpecies-families.stk
03_repeatmasker/            RepeatMasker outputs
    ├── combined_repeat_library.fa  ← merged library used for masking
    ├── genome.fasta.out            ← repeat coordinates
    ├── genome.fasta.gff            ← repeats in GFF format
    └── genome.fasta.softmasked     ← soft-masked FASTA (lowercase = masked)
04_busco_masked/            BUSCO results on masked assembly
05_braker/                  BRAKER3 gene annotation
    ├── braker.gtf                  ← gene models (GTF)
    ├── braker.gff3                 ← gene models (GFF3, if AGAT installed)
    ├── augustus.hints.gtf
    └── braker.log
.stamps/                    Step completion markers (used by make)
```

---

## Choosing BUSCO Lineage

Common lineages – pick the most specific one for your organism:

| Organism group | Lineage dataset |
|---|---|
| Plants (broad) | `embryophyta_odb10` |
| Flowering plants | `eudicots_odb10` or `liliopsida_odb10` |
| Fungi | `fungi_odb10` |
| Insects | `insecta_odb10` |
| Vertebrates | `vertebrata_odb10` |
| Mammals | `mammalia_odb10` |

Full list: https://busco.ezlab.org/list_of_lineages.html

---

## BRAKER3 Evidence Modes

BRAKER3 automatically selects the mode based on what you provide:

| `RNA_BAM` | `PROTEIN_DB` | Mode | Notes |
|---|---|---|---|
| ✓ | ✗ | ET mode | RNA-seq only |
| ✗ | ✓ | EP mode | Proteins only (add `--epmode`) |
| ✓ | ✓ | ETP mode | Best accuracy; recommended |

For proteins, use the **OrthoDB** partitioned protein sets:
https://bioinf.uni-greifswald.de/bioinf/partitioned_odb11/

---

## Tips & Troubleshooting

- **RepeatModeler is slow** – it can take days on large genomes. Run on an HPC with `THREADS := 64` or more.
- **BRAKER3 fails with GeneMark error** – ensure `~/.gm_key` exists and is not expired (keys expire after 1 year).
- **AUGUSTUS species not found** – set `SPECIES_NAME` to a closely related species already in AUGUSTUS: run `augustus --species=help` to list them.
- **Low BUSCO after masking** – some over-masking is normal. If BUSCO drops dramatically (>5%), check the repeat library quality.
- **HPC/SLURM** – wrap each make target in a SLURM job; pass `--jobs N` to make for parallelism: `make -j4 all`.

---

## Cleaning Up

```bash
make clean   # removes all output directories and stamps
```
