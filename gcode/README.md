# gcode - a GitHub Action to generate gcode using Slic3r

This action slices STLs into gcode for your 3D printer. All of this happens around GitHub's infrastructure.

### What do I need to get started?

* A `slic3r` configuration ([Prusa3D's fork](https://github.com/prusa3d/Slic3r/releases)) committed to your repository.

How to get this: When slic3r is open, select your preferred settings (layer height, filament, printer settings). Go to `File -> Export Config` and commit the `.ini` file to your repository somewhere.

* STL files in your repository

These can be placed anywhere in your repository.

* A GitHub Actions workflow

This should be in `.github/main.workflow` and looks something like this:

```
# 'resolves' contains labels which fulfill (or 'resolve') the workflow
# 'on = "push"' will run this workflow on `git push`. 
# Other 'on' types are described here: https://git.io/fhhx5
workflow "generate gcode" {
  resolves = ["gen", "batterybox"]
  on = "push"
}

# 'gen' is named in 'resolves' above.
# 'uses' points to the repository of the action, 
# and will use whatever the '1.41.3' tag/branch/ref points at.
#
# REQUIRED: 'secrets' is where 'GITHUB_TOKEN' is defined. This is provided by GitHub.
# REQUIRED: 'env' holds configuration parameters for the action. 'SLICE_CFG' is a required parameter.
# and should point at the config relative to your repository (see the tree below).
action "gen" {
  uses = "davidk/slic3r-action/gcode@1.41.3"
  args = "cover-jst-access.stl switch/switch8.stl usg/usg.stl pocketchip/pocketchip-clip.stl"
  secrets = ["GITHUB_TOKEN"]
  env = {
    SLICE_CFG = "config.ini"
  }
}

# OPTIONAL: 'EXTRA_SLICER_ARGS' is an optional parameter for passing any other arguments to the slic3r
# N.B. Prusa i3s --print-center 100,100 on a small print may center the object on the thermistor, 
# leading to a thermal runaway error (if the part cooling fan is running)
# the default has been adjusted to --print-center 125,105
action "batterybox" {
  uses = "davidk/slic3r-action/gcode@1.41.3"
  args = "lipoly-battery-box/batterybox.stl"
  secrets = ["GITHUB_TOKEN"]
  env = {
    SLICE_CFG = "config.ini"
    EXTRA_SLICER_ARGS = "--print-center 100,100 --output-filename-format {input_filename_base}_{printer_model}.gcode_updated"
  }
}
```

Your repository might end up looking something like this:

	├── config.ini
	├── cover-jst-access_0.15mm_PET_MK2S.gcode
	├── cover-jst-access.stl
	├── .github
	│   └── main.workflow
	├── lipoly-battery-box
	│   ├── batterybox_0.15mm_PET_MK2S.gcode
	│   ├── batterybox_MK2S.gcode
	│   └── batterybox.stl
	├── pocketchip
	│   ├── pocketchip-clip_0.15mm_PET_MK2S.gcode
	│   └── pocketchip-clip.stl
	├── switch
	│   ├── switch8_0.15mm_PET_MK2S.gcode
	│   └── switch8.stl
	└── usg
	    ├── README.md
	    ├── usg_0.15mm_PET_MK2S.gcode
	    └── usg.stl

### What should I expect

On an event that launches the GitHub Action (like a push), this will run and drop a sliced .gcode file in the same location as the STL. 

The gcode file should be ready for your 3D printer when it's done.