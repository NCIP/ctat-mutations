version 1.0

workflow annotate_variants_wf {
    
    input {
        File input_vcf
        File input_vcf_index
        String base_name

        File ref_fasta
        File ref_fasta_index

        File? bam
        File? bam_index

        # annotation options
        Boolean incl_snpEff = true
        Boolean incl_dbsnp = true
        Boolean incl_gnomad = true
        Boolean incl_rna_editing = true
        Boolean include_read_var_pos_annotations = true
        Boolean incl_repeats = true
        Boolean incl_homopolymers = true
        Boolean incl_splice_dist = true
        Boolean incl_blat_ED = true
        Boolean incl_cosmic = true
        Boolean incl_cravat = true

        Boolean singlecell_mode = false

        File? dbsnp_vcf
        File? dbsnp_vcf_index

        File? gnomad_vcf
        File? gnomad_vcf_index

        File? rna_editing_vcf
        File? rna_editing_vcf_index

        File? cosmic_vcf
        File? cosmic_vcf_index

        File? ref_splice_adj_regions_bed
        
        File? cravat_lib_tar_gz
        String? cravat_lib_dir

        File? repeat_mask_bed

        String? genome_version

        String docker = "trinityctat/ctat_mutations:latest"
        String plugins_path = "/usr/local/src/ctat-mutations/plugins"
        String scripts_path = "/usr/local/src/ctat-mutations/src"

        Int preemptible
        Int cpu
    }


    Boolean vcf_input = defined(vcf)

    parameter_meta {

        left:{help:"One of the two paired RNAseq samples"}
        right:{help:"One of the two paired RNAseq samples"}
        bam:{help:"Previously aligned bam file. When VCF is provided, the output from ApplyBQSR should be provided as the bam input."}
        bai:{help:"Previously aligned bam index file"}
        vcf:{help:"Previously generated vcf file to annotate and filter. When provided, the output from ApplyBQSR should be provided as the bam input."}
        sample_id:{help:"Sample id"}

        # resources
        ref_fasta:{help:"Path to the reference genome to use in the analysis pipeline."}
        ref_fasta_index:{help:"Index for ref_fasta"}
        gtf:{help:"Annotations GTF."}


        dbsnp_vcf:{help:"dbSNP VCF file for the reference genome."}
        dbsnp_vcf_index:{help:"dbSNP vcf index"}

        gnomad_vcf:{help:"gnomad vcf file w/ allele frequencies"}
        gnomad_vcf_index:{help:"gnomad VCF index"}

        rna_editing_vcf:{help:"RNA editing VCF file"}
        rna_editing_vcf_index:{help:"RNA editing VCF index"}

        cosmic_vcf:{help:"Coding Cosmic Mutation VCF annotated with Phenotype Information"}
        cosmic_vcf_index:{help:"COSMIC VCF index"}

        repeat_mask_bed:{help:"bed file containing repetive element (repeatmasker) annotations (from UCSC genome browser download)"}

        ref_splice_adj_regions_bed:{help:"For annotating exon splice proximity"}

        cravat_lib_tar_gz:{help:"CRAVAT resource archive"}
        cravat_lib_dir:{help:"CRAVAT resource directory (for non-Terra / local use where ctat genome lib is installed already)"}

        genome_version:{help:"Genome version for annotating variants using Cravat and SnpEff", choices:["hg19", "hg38"]}

        include_read_var_pos_annotations :{help: "Add vcf annotation that requires variant to be at least 6 bases from ends of reads."}

        plugins_path:{help:"Path to plugins"}
        scripts_path:{help:"Path to scripts"}

        singlecell_mode:{help:"run in single-cell mode and capture the cell barcode to variant info"}

        docker:{help:"Docker or singularity image"}
    }


    call examine_existing_annotations as ExistingAnnots {
        input:
            input_vcf = input_vcf,
            docker = docker,
            preemptible = preemptible
    }    

        
    # leftnorm and split multiallelics

    if (! defined(ExistingAnnots.left_norm_done) ) {
        
        call left_norm_vcf {
            input:
              input_vcf = input_vcf,
              input_vcf_index = input_vcf_index,
              base_name = base_name,
              ref_fasta = ref_fasta,
              ref_fasta_index = ref_fasta_index,
              scripts_path = scripts_path,
              docker = docker,
              preemptible = preemptible
       }
    }

    if (incl_snpEff && ! defined(ExistingAnnots.snpEff_done) ) {

        call snpEff {
            input:
                input_vcf = select_first([left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([left_norm_vcf.vcf_index, input_vcf_index]),
                base_name = base_name,
                scripts_path = scripts_path,
                plugins_path = plugins_path,
                genome_version = select_first([genome_version]),
                docker = docker,
                preemptible = preemptible,
                cpu = cpu
        }
    }


    if (incl_dbsnp && ! defined(ExistingAnnots.dbsnp_done) ) {

        call annotate_dbsnp {
            input:
                input_vcf =  select_first([snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
                dbsnp_vcf = select_first([dbsnp_vcf]),
                dbsnp_vcf_index = select_first([dbsnp_vcf_index]),
                base_name = base_name,
                docker = docker,
                preemptible = preemptible
        }
    }

    if (incl_gnomad && ! defined(ExistingAnnots.gnomad_done) ) {

        call annotate_gnomad {
            input:
                input_vcf = select_first([annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
                gnomad_vcf = select_first([gnomad_vcf]),
                gnomad_vcf_index = select_first([gnomad_vcf_index]),
                base_name = base_name,
                docker = docker,
                preemptible = preemptible
        }
    }
                

    if (incl_rna_editing && ! defined(ExistingAnnots.rna_editing_done) ) {

        call annotate_RNA_editing {
            input:
                input_vcf = select_first([annotate_gnomad.vcf, annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([annotate_gnomad.vcf_index, annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
                rna_editing_vcf = select_first([rna_editing_vcf]),
                rna_editing_vcf_index = select_first([rna_editing_vcf_index]),
                base_name = base_name,
                scripts_path = scripts_path,
                docker = docker,
                preemptible = preemptible
        }
    }

    if ( (include_read_var_pos_annotations || singlecell_mode) && ! defined(ExistingAnnots.pass_read_annots_done) ) {
        
        call annotate_PASS_reads {
            input:
                input_vcf = select_first([annotate_RNA_editing.vcf, annotate_gnomad.vcf, annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([annotate_RNA_editing.vcf_index, annotate_gnomad.vcf_index, annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
                bam = select_first([bam]),
                bam_index = select_first([bam_index]),
                singlecell_mode=singlecell_mode,
                base_name = base_name,
                scripts_path = scripts_path,
                docker = docker,
                preemptible = preemptible,
                cpu = cpu
        }
    }


    if (incl_repeats && ! defined (ExistingAnnots.repeats_done) ) {
    
        call annotate_repeats {
            input:
                input_vcf = select_first([annotate_PASS_reads.vcf, annotate_RNA_editing.vcf, annotate_gnomad.vcf, annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([annotate_PASS_reads.vcf_index, annotate_RNA_editing.vcf_index, annotate_gnomad.vcf_index, annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
                repeat_mask_bed = select_first([repeat_mask_bed]),
                base_name = base_name,
                scripts_path = scripts_path,
                docker = docker,
                preemptible = preemptible,
                cpu = cpu
       }
    }


    if (incl_homopolymers && ! defined(ExistingAnnots.homopolymer_done) ) {

        call annotate_homopolymers_n_entropy {
            input:
                input_vcf = select_first([annotate_repeats.vcf, annotate_PASS_reads.vcf, annotate_RNA_editing.vcf, annotate_gnomad.vcf, annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]), 
                input_vcf_index = select_first([annotate_repeats.vcf_index, annotate_PASS_reads.vcf_index, annotate_RNA_editing.vcf_index, annotate_gnomad.vcf_index, annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
                ref_fasta = ref_fasta,
                ref_fasta_index = ref_fasta_index,
                base_name = base_name,
                scripts_path = scripts_path,
                docker = docker,
                preemptible = preemptible
          }
    }
                
    if (incl_splice_dist && ! defined (ExistingAnnots.splice_dist_done) ) {
        call annotate_splice_distance {
            input:
                input_vcf = select_first([annotate_homopolymers_n_entropy.vcf, annotate_repeats.vcf, annotate_PASS_reads.vcf, annotate_RNA_editing.vcf, annotate_gnomad.vcf, annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([annotate_homopolymers_n_entropy.vcf_index, annotate_repeats.vcf_index, annotate_PASS_reads.vcf_index, annotate_RNA_editing.vcf_index, annotate_gnomad.vcf_index, annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
                ref_splice_adj_regions_bed = select_first([ref_splice_adj_regions_bed]),
                base_name = base_name,
                scripts_path = scripts_path,
                docker = docker,
                preemptible = preemptible
         }
    }


    if (incl_blat_ED && ! defined(ExistingAnnots.blat_ED_done) ) {
        call annotate_blat_ED {
            input:
                input_vcf = select_first([annotate_splice_distance.vcf, annotate_homopolymers_n_entropy.vcf, annotate_repeats.vcf, annotate_PASS_reads.vcf, annotate_RNA_editing.vcf, annotate_gnomad.vcf, annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([annotate_splice_distance.vcf_index,  annotate_homopolymers_n_entropy.vcf_index, annotate_repeats.vcf_index, annotate_PASS_reads.vcf_index, annotate_RNA_editing.vcf_index, annotate_gnomad.vcf_index, annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
                ref_fasta = ref_fasta,
                ref_fasta_index = ref_fasta_index,
                base_name = base_name,
                scripts_path = scripts_path,
                docker = docker,
                preemptible = preemptible,
                cpu = cpu
        }

    }


    if (incl_cosmic && ! defined(ExistingAnnots.COSMIC_done) ) {
        call annotate_cosmic_variants {
            input:
                input_vcf = select_first([annotate_blat_ED.vcf, annotate_splice_distance.vcf, annotate_homopolymers_n_entropy.vcf, annotate_repeats.vcf, annotate_PASS_reads.vcf, annotate_RNA_editing.vcf, annotate_gnomad.vcf, annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([annotate_blat_ED.vcf_index, annotate_splice_distance.vcf_index,  annotate_homopolymers_n_entropy.vcf_index, annotate_repeats.vcf_index, annotate_PASS_reads.vcf_index, annotate_RNA_editing.vcf_index, annotate_gnomad.vcf_index, annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]), 
                cosmic_vcf = select_first([cosmic_vcf]),
                cosmic_vcf_index = select_first([cosmic_vcf_index]),
                base_name = base_name,
                scripts_path = scripts_path,
                docker = docker,
                preemptible = preemptible
        }

    }

    if (incl_cravat && ! defined(ExistingAnnots.CRAVAT_done) ) {
         
        call open_cravat {
            input:
                input_vcf = select_first([annotate_cosmic_variants.vcf, annotate_blat_ED.vcf, annotate_splice_distance.vcf, annotate_homopolymers_n_entropy.vcf, annotate_repeats.vcf, annotate_PASS_reads.vcf, annotate_RNA_editing.vcf, annotate_gnomad.vcf, annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
                input_vcf_index = select_first([annotate_cosmic_variants.vcf_index, annotate_blat_ED.vcf_index, annotate_splice_distance.vcf_index,  annotate_homopolymers_n_entropy.vcf_index, annotate_repeats.vcf_index, annotate_PASS_reads.vcf_index, annotate_RNA_editing.vcf_index, annotate_gnomad.vcf_index, annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
                cravat_lib_tar_gz = cravat_lib_tar_gz,
                cravat_lib_dir = cravat_lib_dir,
                genome_version = select_first([genome_version]),
                base_name = base_name,
                scripts_path = scripts_path,
                docker = docker,
                preemptible = preemptible
        }
    }


    call rename_vcf {
        input:
            input_vcf = select_first([open_cravat.vcf, annotate_cosmic_variants.vcf, annotate_blat_ED.vcf, annotate_splice_distance.vcf, annotate_homopolymers_n_entropy.vcf, annotate_repeats.vcf, annotate_PASS_reads.vcf, annotate_RNA_editing.vcf, annotate_gnomad.vcf, annotate_dbsnp.vcf, snpEff.vcf, left_norm_vcf.vcf, input_vcf]),
            input_vcf_index = select_first([open_cravat.vcf_index, annotate_cosmic_variants.vcf_index, annotate_blat_ED.vcf_index, annotate_splice_distance.vcf_index,  annotate_homopolymers_n_entropy.vcf_index, annotate_repeats.vcf_index, annotate_PASS_reads.vcf_index, annotate_RNA_editing.vcf_index, annotate_gnomad.vcf_index, annotate_dbsnp.vcf_index, snpEff.vcf_index, left_norm_vcf.vcf_index, input_vcf_index]),
            base_name = base_name,
            docker=docker,
            preemptible=preemptible

    }


   output {
    
        File vcf = rename_vcf.vcf
        File vcf_index = rename_vcf.vcf_index
        File? sc_var_reads = annotate_PASS_reads.sc_var_reads
    
    }
}


task left_norm_vcf {
    input {
        File input_vcf
        File input_vcf_index
        String base_name
        File ref_fasta
        File ref_fasta_index
        String scripts_path

        String docker
        Int preemptible
        Int cpu = 1
        Int disk = ceil((size(input_vcf, "GB") * 3) + 50)
        
    }

    command <<<
        set -ex

        echo "####### leftnorm and split multiallelics ##########"
      
        # leftnorm and split multiallelics
        bcftools norm \
        -f ~{ref_fasta} \
        -m -any \
        -o ~{base_name}.norm.vcf \
        ~{input_vcf}

        ~{scripts_path}/groom_vcf.py ~{base_name}.norm.vcf ~{base_name}.norm.groom.vcf

        bcftools sort -T . ~{base_name}.norm.groom.vcf > ~{base_name}.norm.groom.sorted.vcf
        bgzip -c ~{base_name}.norm.groom.sorted.vcf > ~{base_name}.norm.groom.sorted.vcf.gz
        tabix ~{base_name}.norm.groom.sorted.vcf.gz

   >>>

    output {
        File vcf = "~{base_name}.norm.groom.sorted.vcf.gz"
        File vcf_index = "~{base_name}.norm.groom.sorted.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "16G"
        preemptible: preemptible
        cpu : cpu
    }


}


task snpEff {

    input {
        File input_vcf
        File input_vcf_index
        String base_name
        String scripts_path
        String base_name
        String plugins_path
        String genome_version

        String docker
        Int preemptible
        Int cpu
        Int disk = ceil((size(input_vcf, "GB") * 3) + 50)
   
    }


    command <<<

        set -ex


        echo "######### SnpEFF #########"
      
        bgzip -cd ~{input_vcf} | \
            java -Xmx3500m -jar ~{plugins_path}/snpEff.jar \
            -nostats -noLof -no-downstream -no-upstream -noLog \
            ~{genome_version} > ~{base_name}.snpeff.tmp.vcf

        ~{scripts_path}/update_snpeff_annotations.py \
            ~{base_name}.snpeff.tmp.vcf \
            ~{base_name}.snpeff.vcf

        bgzip -c ~{base_name}.snpeff.vcf > ~{base_name}.snpeff.vcf.gz
        tabix ~{base_name}.snpeff.vcf.gz
           

    >>>

    output {
        File vcf = "~{base_name}.snpeff.vcf.gz"
        File vcf_index = "~{base_name}.snpeff.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "16G"
        preemptible: preemptible
        cpu : cpu
    }

}


task annotate_dbsnp {

    input {
        File input_vcf
        File input_vcf_index
        File dbsnp_vcf
        File dbsnp_vcf_index
        String base_name

        String docker
        Int preemptible
        Int cpu = 1
        Int disk = ceil((size(input_vcf, "GB") * 3) + 50)
    }

    command <<<
        set -ex

        echo "####### Annotate dbSNP ########"
      
        bcftools annotate \
            --output-type z \
            --annotations ~{dbsnp_vcf} \
            --columns "INFO/OM,INFO/PM,INFO/SAO,INFO/RS" \
            --output ~{base_name}.dbsnp.vcf.gz \
            ~{input_vcf}
            tabix ~{base_name}.dbsnp.vcf.gz

    >>>

    output {
        File vcf = "~{base_name}.dbsnp.vcf.gz"
        File vcf_index = "~{base_name}.dbsnp.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "16G"
        preemptible: preemptible
        cpu : cpu
    }

}


task annotate_gnomad {

    input {
        File input_vcf
        File input_vcf_index
        File gnomad_vcf
        File gnomad_vcf_index
        String base_name

        String docker
        Int preemptible
        Int cpu = 1
        Int disk = ceil((size(input_vcf, "GB") * 3) + 50)
    }

    command <<<
        set -ex

        echo "####### Annotate gnomAD ########"

      
        bcftools annotate \
            --output-type z \
            --annotations ~{gnomad_vcf} \
            --columns "INFO/gnomad_RS,INFO/gnomad_AF" \
            --output ~{base_name}.gnomad.vcf.gz \
            ~{input_vcf}

            tabix ~{base_name}.gnomad.vcf.gz

    >>>

    output {
        File vcf = "~{base_name}.gnomad.vcf.gz"
        File vcf_index = "~{base_name}.gnomad.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "16G"
        preemptible: preemptible
        cpu : cpu
    }

}


task annotate_RNA_editing {

    input {
        File input_vcf
        File input_vcf_index
        File rna_editing_vcf
        File rna_editing_vcf_index
        String base_name
        String scripts_path

        String docker
        Int preemptible
        Int cpu = 1
        Int disk = ceil((size(input_vcf, "GB") * 3) + 50)
    }

    command <<<
        set -ex


         echo "######### Annotate RNA Editing #############"
      
         bcftools annotate \
            --output-type z \
            --annotations ~{rna_editing_vcf} \
            --columns "INFO/RNAEDIT" \
            --output ~{base_name}.rna_editing.gz \
            ~{input_vcf}

        #must groom for gatk compat
        ~{scripts_path}/groom_vcf.py ~{base_name}.rna_editing.gz ~{base_name}.rna_editing.groom.vcf


        bgzip -c ~{base_name}.rna_editing.groom.vcf > ~{base_name}.rna_editing.groom.vcf.gz
        tabix ~{base_name}.rna_editing.groom.vcf.gz


    >>>

    output {
        File vcf = "~{base_name}.rna_editing.groom.vcf.gz"
        File vcf_index = "~{base_name}.rna_editing.groom.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "16G"
        preemptible: preemptible
        cpu : cpu
    }

}


task annotate_PASS_reads {

    input {
        File input_vcf
        File input_vcf_index
        File bam
        File bam_index
        String base_name
        String scripts_path
        Boolean singlecell_mode

        String docker
        Int preemptible
        Int cpu
        Int disk = ceil((size(bam, "GB") * 4) + (size(input_vcf, "GB") * 10) + 20)
        
    }


    command <<<

        set -ex

        echo "######## Annotate PASS Reads #########"
      
        samtools index ~{bam}

        ~{scripts_path}/annotate_PASS_reads.extract_sc_info.py \
            --vcf ~{input_vcf}  \
            --bam ~{bam} \
            ~{true='--sc_mode' false='' singlecell_mode} \
            --output_vcf ~{base_name}.annot_pass_reads.vcf \
            --threads ~{cpu}

            bgzip -c ~{base_name}.annot_pass_reads.vcf > ~{base_name}.annot_pass_reads.vcf.gz
            tabix ~{base_name}.annot_pass_reads.vcf.gz

        if [ -e ~{base_name}.annot_pass_reads.vcf.sc_reads ]; then
               gzip ~{base_name}.annot_pass_reads.vcf.sc_reads
        fi

    >>>


    output {
        File vcf = "~{base_name}.annot_pass_reads.vcf.gz"
        File vcf_index = "~{base_name}.annot_pass_reads.vcf.gz.tbi"
        File? sc_var_reads = "~{base_name}.annot_pass_reads.vcf.sc_reads.gz"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "16G"
        preemptible: preemptible
        cpu : cpu
    }

}


task annotate_repeats {
    input {
        File input_vcf
        File input_vcf_index

        File repeat_mask_bed

        String base_name
        String scripts_path

        String docker
        Int preemptible
        Int cpu
        Int disk = ceil((size(input_vcf, "GB") * 3) + 20)
       
    }

    command <<<

        set -ex

        echo "####### Annotate Repeats #########"

      
        ~{scripts_path}/annotate_repeats.py \
            --input_vcf ~{input_vcf} \
            --repeats_bed ~{repeat_mask_bed} \
            --output_vcf ~{base_name}.annot_repeats.vcf

            bgzip -c ~{base_name}.annot_repeats.vcf > ~{base_name}.annot_repeats.vcf.gz

            tabix ~{base_name}.annot_repeats.vcf.gz
    >>>


    output {
        File vcf = "~{base_name}.annot_repeats.vcf.gz"
        File vcf_index = "~{base_name}.annot_repeats.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "16G"
        preemptible: preemptible
        cpu : cpu
    }

}


task annotate_homopolymers_n_entropy {

    input {
        File input_vcf
        File input_vcf_index

        File ref_fasta
        File ref_fasta_index

        String base_name
        String scripts_path

        String docker
        Int preemptible
        Int cpu = 1
        Int disk = ceil((size(input_vcf, "GB") * 3) + 50)
    }

    command <<<

        set -ex

         echo "########## Annotate Entropy and Homopolymers ###############"
      
         ~{scripts_path}/annotate_entropy_n_homopolymers.py \
            --input_vcf ~{input_vcf} \
            --ref_genome_fa ~{ref_fasta} \
            --tmpdir $TMPDIR \
            --output_vcf ~{base_name}.homopolymer.vcf

            bgzip -c ~{base_name}.homopolymer.vcf > ~{base_name}.homopolymer.vcf.gz
            tabix ~{base_name}.homopolymer.vcf.gz

    >>>


    output {
        File vcf = "~{base_name}.homopolymer.vcf.gz"
        File vcf_index = "~{base_name}.homopolymer.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "16G"
        preemptible: preemptible
        cpu : cpu
    }

}


task annotate_splice_distance {

    input {
        File input_vcf
        File input_vcf_index

        File ref_splice_adj_regions_bed

        String base_name
        String scripts_path

        String docker
        Int preemptible
        Int cpu = 1
        Int disk = ceil((size(input_vcf, "GB") * 3) + 20)

    }


    command <<<

        set -ex


        echo "########## Annotate Splice Distance ##############"
      
        ~{scripts_path}/annotate_DJ.py \
            --input_vcf ~{input_vcf} \
            --splice_bed ~{ref_splice_adj_regions_bed} \
            --temp_dir $TMPDIR \
            --output_vcf ~{base_name}.splice_distance.vcf

        bgzip -c ~{base_name}.splice_distance.vcf > ~{base_name}.splice_distance.vcf.gz
        tabix ~{base_name}.splice_distance.vcf.gz

    >>>


    output {
        File vcf = "~{base_name}.splice_distance.vcf.gz"
        File vcf_index = "~{base_name}.splice_distance.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "16G"
        preemptible: preemptible
        cpu : cpu
    }

}    


task annotate_blat_ED {

    input {
        File input_vcf
        File input_vcf_index

        File ref_fasta
        File ref_fasta_index

        String base_name
        String scripts_path

        String docker
        Int preemptible
        Int cpu
        Int disk = ceil((size(input_vcf, "GB") * 3) + 200)

    }


    command <<<

        set -ex
      
        echo "########### Annotate BLAT ED #############"
      
        if [ ! -d tmpdir ]; then
            mkdir tmpdir
        fi

        ~{scripts_path}/annotate_ED.py \
            --input_vcf ~{input_vcf} \
            --output_vcf ~{base_name}.blat_ED.vcf \
            --reference ~{ref_fasta} \
            --temp_dir tmpdir \
            --threads ~{cpu}

            bgzip -c ~{base_name}.blat_ED.vcf > ~{base_name}.blat_ED.vcf.gz
            tabix ~{base_name}.blat_ED.vcf.gz

    >>>


    output {
        File vcf = "~{base_name}.blat_ED.vcf.gz"
        File vcf_index = "~{base_name}.blat_ED.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "40G"
        preemptible: preemptible
        cpu : cpu
    }

}    




task annotate_cosmic_variants {

    input {
        File input_vcf
        File input_vcf_index

        File cosmic_vcf
        File cosmic_vcf_index

        String base_name
        String scripts_path

        String docker
        Int preemptible
        Int cpu = 1
        Int disk = ceil((size(input_vcf, "GB") * 3) + 20)

    }


    command <<<

        set -ex

        echo "############# Annotate COSMIC Variants ################"
      
        bcftools annotate \
            --annotations ~{cosmic_vcf} \
            --columns "INFO/COSMIC_ID,INFO/TISSUE,INFO/TUMOR,INFO/FATHMM,INFO/SOMATIC" \
            --output ~{base_name}.annot_cosmic.tmp.vcf \
            ~{input_vcf}


            #must groom for gatk compat
            ~{scripts_path}/groom_vcf.py \
                ~{base_name}.annot_cosmic.tmp.vcf ~{base_name}.annot_cosmic.vcf
      
            bgzip ~{base_name}.annot_cosmic.vcf
      
            tabix ~{base_name}.annot_cosmic.vcf.gz

    >>>

    output {
        File vcf = "~{base_name}.annot_cosmic.vcf.gz"
        File vcf_index = "~{base_name}.annot_cosmic.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "4G"
        preemptible: preemptible
        cpu : cpu
    }

}    




task open_cravat {

    input {
        File input_vcf
        File input_vcf_index

        # must specify cravat_lib_dir or cravat_lib_tar_gz
        File? cravat_lib_tar_gz #providing the tar.gz file with the cravat resources
        String? cravat_lib_dir  #path to existing cravat lib dir in the ctat genome lib
        String genome_version

        String base_name
        String scripts_path

        String docker
        Int preemptible
        Int cpu = 1
        Int disk = ceil((size(input_vcf, "GB") * 3) + 50 + if(defined(cravat_lib_tar_gz))then 100 else 0)
        

    }


    command <<<

        set -ex

        echo "########### Annotate CRAVAT #############"

        cravat_lib_dir="~{cravat_lib_dir}"
        # cravat
        if [ "$cravat_lib_dir" == "" ]; then
            
            if [ "~{cravat_lib_tar_gz}" == "" ]; then
                 echo "Error, must specify cravat_lib_tar_gz or cravat_lib path"
                 exit 1
            fi
            
            #use the provided tar.gz cravat lib      
            cravat_lib_dir="~{cravat_lib_tar_gz}"

            mkdir cravat_lib_dir
            compress="pigz"

            if [[ $cravat_lib_dir == *.bz2 ]] ; then
                compress="pbzip2"
            fi

            tar -I $compress -xf $cravat_lib_dir -C cravat_lib_dir --strip-components 1
            cravat_lib_dir="cravat_lib_dir"

        fi
        
        export TMPDIR=/tmp # https://github.com/broadinstitute/cromwell/issues/3647

        ~{scripts_path}/annotate_with_cravat.py \
            --input_vcf ~{input_vcf} \
            --genome ~{genome_version} \
            --cravat_lib_dir $cravat_lib_dir \
            --output_vcf ~{base_name}.cravat.tmp.vcf

            #must groom for gatk compat
            ~{scripts_path}/groom_vcf.py \
                ~{base_name}.cravat.tmp.vcf ~{base_name}.cravat.groom.vcf

            bcftools sort -T . ~{base_name}.cravat.groom.vcf > ~{base_name}.cravat.vcf
            bgzip -c ~{base_name}.cravat.vcf > ~{base_name}.cravat.vcf.gz
            tabix ~{base_name}.cravat.vcf.gz

        

    >>>

    output {
        File vcf = "~{base_name}.cravat.vcf.gz"
        File vcf_index = "~{base_name}.cravat.vcf.gz.tbi"
    }

    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "4G"
        preemptible: preemptible
        cpu : cpu
    }

}    


task rename_vcf {
    input {
        File input_vcf
        File input_vcf_index
        String base_name

        String docker        
        Int preemptible
        Int cpu = 1
        Int disk = ceil((size(input_vcf, "GB") * 2)) 
    }


    command <<<

        set -ex

        echo "####### Final step: Renaming Vcf ########"
      
        mv ~{input_vcf} ~{base_name}.vcf.gz
        mv ~{input_vcf}.tbi ~{base_name}.vcf.gz.tbi

     >>>



    output {
        File vcf = "~{base_name}.vcf.gz"
        File vcf_index = "~{base_name}.vcf.gz.tbi"
    }
	
    runtime {
        disks: "local-disk " + disk + " HDD"
        docker: docker
        memory: "4G"
        preemptible: preemptible
        cpu : cpu
    }

}

task examine_existing_annotations {
    input {
        File input_vcf
        String docker
        Int preemptible
    }

    Int disk_size = ceil((size(input_vcf, "GB") * 3) + 10)

    
    command <<<
        set -ex
        
        python <<CODE
        import gzip, re, subprocess

        input_vcf="~{input_vcf}"
        
        if re.search("\\.gz$", input_vcf):
            fh = gzip.open(input_vcf, "rt")
        else:
            fh = open(input_vcf, "rt")

        header = ""
        for line in fh:
            if line[0] == "#":
                header += line
            else:
                break # done reading header
        
        # check header for various annots
        checkpoints = list()
        if re.search("##bcftools_normCommand=norm", header) is not None:
            checkpoints.append("left_norm.done")

        if re.search("##INFO=<ID=ANN,", header) is not None:
            checkpoints.append("snpEff.done")
        
        if re.search("##INFO=<ID=RS,", header) is not None:
            checkpoints.append("dbsnp.done")

        if re.search("##INFO=<ID=gnomad_AF,", header) is not None:
            checkpoints.append("gnomad.done")

        
        if re.search("##INFO=<ID=RNAEDIT,", header) is not None:
            checkpoints.append("rna_editing.done")

        if re.search("##INFO=<ID=VPR,", header) is not None:
            checkpoints.append("pass_read_annots.done")


        if re.search("##INFO=<ID=RPT,", header) is not None:
            checkpoints.append("repeats.done")

        if re.search("##INFO=<ID=Homopolymer,", header) is not None:
            checkpoints.append("homopolymer.done")

        if re.search("##INFO=<ID=DJ,", header) is not None:
            checkpoints.append("splice_dist.done")

        if re.search("##INFO=<ID=ED,", header) is not None:
            checkpoints.append("blat_ED.done")

        if re.search("##INFO=<ID=COSMIC_ID,", header) is not None:
            checkpoints.append("COSMIC.done")

        if re.search("##INFO=<ID=chasmplus_pval,", header) is not None and re.search("##INFO=<ID=vest_pval,", header) is not None:
            checkpoints.append("CRAVAT.done")


        for checkpoint in checkpoints:
            subprocess.check_call(f"touch {checkpoint}", shell=True)

        CODE

        set +e
        
        echo "checking done annotations:"
        ls *.done

        echo "done checking"
        
    >>>


    output {

        File? left_norm_done = "left_norm.done"
        File? snpEff_done = "snpEff.done"
        File? dbsnp_done = "dbsnp.done"
        File? gnomad_done = "gnomad.done"
        File? rna_editing_done = "rna_editing.done"
        File? pass_read_annots_done = "pass_read_annots.done"
        File? repeats_done = "repeats.done"
        File? homopolymer_done = "homopolymer.done"
        File? splice_dist_done = "splice_dist.done"
        File? blat_ED_done = "blat_ED.done"
        File? COSMIC_done = "COSMIC.done"
        File? CRAVAT_done = "CRAVAT.done"

    }

    runtime {
        memory: "2.5 GB"
        disks: "local-disk " + disk_size + " HDD"
        docker: docker
        preemptible: preemptible
    }    
        
}

        
        
        
        
