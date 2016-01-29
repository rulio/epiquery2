hogan     = require 'hogan.js'
dot       = require 'dot'
async     = require 'async'
log       = require 'simplog'
fs        = require 'fs'
path      = require 'path'
_         = require 'underscore'
config    = require './config.coffee'

getRelativeTemplatePath = (templatePath) ->
  # as per the MDN
  #   If either argument is greater than stringName.length,
  #   it is treated as if it were stringName.length.
  templatePath.substring(config.templateDirectory.length + 1, 9999)

# whitespace is important, we don't want to strip it
dot.templateSettings.strip = false

# precompiled templates loaded by hogan during initilization
hoganTemplates = null

# keep track of our renderers, we're storing them by
# their associated file extension as that is how we'll
# be looking them up
renderers = {}
renderers[".dot"] =  (templatePath, context, cb) ->
  log.debug "rendering #{templatePath} with dot renderer"
  fs.readFile templatePath, {encoding: 'utf8'}, (err, templateString) ->
    templateFn = dot.template templateString
    if err
      cb(err)
    else
      cb(null, templateString, templateFn(context))

renderers[".mustache"] =  (templatePath, context, cb) ->
  log.debug "rendering #{templatePath} with mustache renderer"
  relativeTemplatePath = getRelativeTemplatePath(templatePath)
  log.debug "looking for template #{relativeTemplatePath}"
  template = hoganTemplates[relativeTemplatePath]
  log.debug "using hogan template #{relativeTemplatePath}"
  if template
    cb(null, template, template.render(context, hoganTemplates))
  else
    cb(new Error("could not find template: #{relativeTemplatePath}"))

# set our default handler, which does nothing
# but return the the contents of the template it was provided
renderers[""] = (templatePath, _, cb) ->
  log.debug "rendering #{templatePath} with generic renderer"
  fs.readFile templatePath, {encoding: 'utf8'}, (err, templateString) ->
    if err
      cb(err)
    else
      cb(null, templateString, templateString)

getRendererForTemplate = (templatePath) ->
  renderer = renderers[path.extname templatePath]
  # have a 'default' renderer for any unrecognized extensions
  if renderer
    return renderer
  else
    return renderers[""]

getMustacheFiles = (templateDirectory, fileList=[]) ->
  names = fs.readdirSync(templateDirectory)
  _.each names, (name) ->
    fullPath = path.join(templateDirectory, name)
    stat = fs.statSync(fullPath)
    if stat.isDirectory()
      # never descend into a directory named git
      return if name is ".git"
      getMustacheFiles(fullPath, fileList)
    else
      fileList.push(fs.realpathSync(fullPath)) if path.extname(name) is ".mustache"
  fileList

initialize = () ->
  # allows for any initialization a template provider needs to do
  # in this case we'll be compiling all the mustache templates so that
  # we can use partials. Any state created by this process will be 
  # swapped with existing state when initialize is complete, this 
  # will allow initialize to be run while epiquery is active
  #
  log.debug("precompiling mustache templates from #{config.templateDirectory}")
  mustachePaths = getMustacheFiles(config.templateDirectory)
  log.debug("precompiled #{mustachePaths.length} mustache templates")
  templates = {}
  # compile all of the templates
  _.each mustachePaths, (mustachePath) ->
      try
        # we're going to use a key relative to the root of our template directory, as it
        # is epxected that the templates will be stored in their own repository and used
        # anywhere, and we'll remove the leading / so it's clear that the path is relative
        templates[getRelativeTemplatePath(mustachePath)] = hogan.compile(fs.readFileSync(mustachePath).toString())
      catch e
        log.error "error precompiling template #{mustachePath}, it will be skipped"
        log.error e
  log.debug _.keys(templates)
  # swap in the newly loaded templates
  hoganTemplates = templates

module.exports.init = initialize
module.exports.renderTemplate = (templatePath, context, cb) ->
  renderer = getRendererForTemplate(templatePath)
  renderer(templatePath, context, cb)
