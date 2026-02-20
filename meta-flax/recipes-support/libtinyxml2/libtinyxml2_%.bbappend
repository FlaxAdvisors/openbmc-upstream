# The static library contains references to TMPDIR which triggers
# the buildpaths QA error. Suppress for this recipe.
INSANE_SKIP:${PN}-staticdev += "buildpaths"
