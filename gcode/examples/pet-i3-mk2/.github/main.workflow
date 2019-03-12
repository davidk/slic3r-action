workflow "generate gcode" {
  resolves = ["esp8266 huzzah cover", "esp8266 huzzah case", "screw funnel"]
  on = "push"
}

action "esp8266 huzzah cover" {
  uses = "davidk/slic3r-action/gcode@updates"
  args = "cover.stl"
  secrets = ["GITHUB_TOKEN"]
  env = {
    SLICE_CFG = "config.ini"
    EXTRA_SLICER_ARGS = "--output-filename-format {input_filename_base}_{printer_model}.gcode_updated"
  }
}

action "esp8266 huzzah case" {
  uses = "davidk/slic3r-action/gcode@updates"
  args = "case_with_bottom_cutout.stl"
  secrets = ["GITHUB_TOKEN"]
  env = {
    SLICE_CFG = "config.ini"
  }
}

action "screw funnel" {
  uses = "davidk/slic3r-action/gcode@updates"
  args = "screw-funnel.stl"
  secrets = ["GITHUB_TOKEN"]
  env = {
    SLICE_CFG = "config-vase.ini"
    BRANCH = "master"
  }
}
