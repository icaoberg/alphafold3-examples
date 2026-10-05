--
-- AlphaFold 3 modulefile
--
-- "URL: https://www.psc.edu/resources/software"
-- "Category: Biological Sciences"
-- "Description: AlphaFold 3 biomolecular structure prediction (Apptainer container)."
-- "Keywords: protein structure, structure prediction, deep learning"

-- Install as /opt/modulefiles/alphafold3/<version>.lua. For one module per
-- container in $AF3_IMAGES, copy this file and change version to match.
local version = "3.0.4"

whatis("Name: AlphaFold 3")
whatis("Version: " .. version)
whatis("Category: Biological Sciences")
whatis("URL: https://www.psc.edu/resources/software")
whatis("Description: AlphaFold 3 biomolecular structure prediction (Apptainer container).")

help([[
AlphaFold 3 ]] .. version .. [[

----------------

Description
-----------
AlphaFold 3 predicts the structure of proteins, DNA, RNA, ligands, ions and
their complexes. It runs from an Apptainer container, with the genetic
databases and model weights kept on /ocean.

Use the weights only under the terms in $AF3_WEIGHTS/WEIGHTS_TERMS_OF_USE.md.

To load the module type

> module load alphafold3/]] .. version .. [[


Environment variables
---------------------
AF3_VERSION    AlphaFold 3 version of this module
AF3_ROOT       Top of the AlphaFold 3 dataset on /ocean
AF3_IMAGES     Directory holding the AlphaFold 3 containers, one per version
AF3_IMAGE      Container for this version
AF3_DATABASES  Genetic databases, for --db_dir (stage 1, data pipeline)
AF3_WEIGHTS    Model weights, for --model_dir (stage 2, inference)
AF3_CODE       AlphaFold 3 source code, for reference

AF3_DB_DIR and AF3_MODEL_DIR are also set, to the same values as
AF3_DATABASES and AF3_WEIGHTS, because the stage1.sh and stage2.sh example
scripts read those names.

Running
-------
run_alphafold runs run_alphafold.py inside the container, with /ocean,
$PROJECT and $LOCAL bound and GPU support turned on when a GPU is present.
For example, the data pipeline alone on a RM-shared node:

> run_alphafold --json_path=fold_input.json --db_dir=$AF3_DATABASES \
    --output_dir=output --norun_inference

and inference alone on a GPU-shared node:

> run_alphafold --json_path=output/<name>/<name>_data.json \
    --model_dir=$AF3_WEIGHTS --output_dir=output --norun_data_pipeline

Documentation
-------------
https://github.com/google-deepmind/alphafold3
]])

local root   = "/ocean/datasets/community/alphafold3"
local images = "/ocean/containers/alphafold3"
local image  = pathJoin(images, "singularity-alphafold3-v" .. version .. ".sif")

if mode() == "load" and not isFile(image) then
  LmodError("AlphaFold 3 container not found: " .. image)
end

setenv("AF3_VERSION",   version)
setenv("AF3_ROOT",      root)
setenv("AF3_IMAGES",    images)
setenv("AF3_IMAGE",     image)
setenv("AF3_DATABASES", pathJoin(root, "databases"))
setenv("AF3_WEIGHTS",   pathJoin(root, "weights"))
setenv("AF3_CODE",      pathJoin(root, "code", "alphafold3"))

-- Names read by the example stage1.sh and stage2.sh scripts.
setenv("AF3_DB_DIR",    pathJoin(root, "databases"))
setenv("AF3_MODEL_DIR", pathJoin(root, "weights"))

-- Run run_alphafold.py in the container. --nv is added only when nvidia-smi
-- finds a GPU, so the same command works on RM and GPU nodes. $PROJECT and
-- $LOCAL are bound only when they are set. Lmod joins the body onto one line,
-- so each command must end with a semicolon.
local bash_func = table.concat({
  'local nv="" binds="/ocean${PROJECT:+,$PROJECT}${LOCAL:+,$LOCAL}";',
  'nvidia-smi -L >/dev/null 2>&1 && nv="--nv";',
  'apptainer exec $nv --bind "$binds"',
  '"$AF3_IMAGE" python /app/alphafold/run_alphafold.py "$@";',
}, " ")
local csh_func = 'apptainer exec --bind /ocean "$AF3_IMAGE" python /app/alphafold/run_alphafold.py $*'
set_shell_function("run_alphafold", bash_func, csh_func)
