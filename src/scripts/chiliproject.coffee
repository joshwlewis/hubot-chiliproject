# #<issue-id> - One line issue preview.
# (chili|show) me <issue-id>     - Show the issue status
# show (my|user's) issues          - Show your issues or another user's issues
# assign <issue-id> to <user-first-name> ["notes"]  - Assign the issue to the user (searches login or firstname)
#                                                     *With optional notes
# update <issue-id> with "<note>"  - Adds a note to the issue
# add <hours> hours to <issue-id> ["comments"]  - Adds hours to the issue with the optional comments
# link me <issue-id> - Returns a link to the ChiliProject issue
# set <issue-id> to <int>% ["comments"] - Updates an issue and sets the percent done
#
#
# Note: <issue-id> can be formatted in the following ways:
#       1234, #1234, issue 1234, issue #1234
#
#---
#
# Showing of ChiliProject issuess via the REST API.
#
#
#   heroku config:add HUBOT_CHILIPROJECT_BASE_URL="http://chili.your-server.com"
#   heroku config:add HUBOT_CHILIPROJECT_TOKEN="your api token here"
#
# If you are using ChiliProject over HTTPS, add the following config option
#
#   heroku config:add HUBOT_CHILIPROJECT_SSL=1
#
# There may be issues if you have a lot of ChiliProject users sharing a first name, but this can be avoided
# by using ChiliProject logins rather than firstnames
#
if process.env.HUBOT_CHILIPROJECT_SSL?
  HTTP = require('https')
else
  HTTP = require('http')

URL = require('url')
QUERY = require('querystring')

module.exports = (robot) ->
  chili = new Chili process.env.HUBOT_CHILIPROJECT_BASE_URL, process.env.HUBOT_CHILIPROJECT_TOKEN

  # Robot link me <issue>
  robot.respond /link me (?:issue )?(?:#)?(\d+)/i, (msg) ->
    id = msg.match[1]
    msg.reply "#{chili.url}/issues/#{id}"

  # Robot set <issue> to <percent>% ["comments"]
  robot.respond /set (?:issue )?(?:#)?(\d+) to (\d{1,3})%?(?: "?([^"]+)"?)?/i, (msg) ->
    [id, percent, notes] = msg.match[1..3]
    percent = parseInt percent

    if notes?
      notes = "#{msg.message.user.name}: #{userComments}"
    else
      notes = "Ratio set by: #{msg.message.user.name}"

    attributes =
      "notes": notes
      "done_ratio": percent

    chili.Issue(id).update attributes, (err, data, status) ->
      if status == 200
        msg.reply "Set ##{id} to #{percent}%"
      else
        msg.reply "Update failed! (#{err})"

  # Robot add <hours> hours to <issue_id> ["comments for the time tracking"]
  robot.respond /add (\d{1,2}) hours? to (?:issue )?(?:#)?(\d+)(?: "?([^"]+)"?)?/i, (msg) ->
    [hours, id, userComments] = msg.match[1..3]
    hours = parseInt hours

    if userComments?
      comments = "#{msg.message.user.name}: #{userComments}"
    else
      comments = "Time logged by: #{msg.message.user.name}"

    attributes =
      "issue_id": id
      "hours": hours
      "comments": comments

    chili.TimeEntry(null).create attributes, (error, data, status) ->
      if status == 201
        msg.reply "Your time was logged"
      else
        msg.reply "Nothing could be logged. Make sure ChiliProject has a default activity set for time tracking. (Settings -> Enumerations -> Activities)"

  # Robot show <my|user's> [chili] issues
  robot.respond /show (?:my|(\w+\'s)) (?:chili )?issues/i, (msg) ->
    userMode = true
    firstName =
      if msg.match[1]?
        userMode = false
        msg.match[1].replace(/\'.+/, '')
      else
        msg.message.user.name.split(/\s/)[0]

    chili.Users name:firstName, (err,data) ->
      unless data.total_count > 0
        msg.reply "Couldn't find any users with the name \"#{firstName}\""
        return false

      user = resolveUsers(firstName, data.users)[0]

      params =
        "assigned_to_id": user.id
        "limit": 25,
        "status_id": "open"
        "sort": "priority:desc",

      chili.Issues params, (err, data) ->
        if err?
          msg.reply "Couldn't get a list of issues for you!"
        else
          _ = []

          if userMode
            _.push "You have #{data.total_count} issue(s)."
          else
            _.push "#{user.firstname} has #{data.total_count} issue(s)."

          for issue in data.issues
            do (issue) ->
              _.push "\n[#{issue.tracker.name} - #{issue.priority.name} - #{issue.status.name}] ##{issue.id}: #{issue.subject}"

          msg.reply _.join "\n"

  # Robot update <issue> with "<note>"
  robot.respond /update (?:issue )?(?:#)?(\d+)(?:\s*with\s*)?(?:[-:,])? (?:"?([^"]+)"?)/i, (msg) ->
    [id, note] = msg.match[1..2]

    attributes =
      "notes": "#{msg.message.user.name}: #{note}"

    chili.Issue(id).update attributes, (err, data, status) ->
      unless data?
        if status == 404
          msg.reply "Issue ##{id} doesn't exist."
        else
          msg.reply "Couldn't update this issue, sorry :("
      else
        msg.reply "Done! Updated ##{id} with \"#{note}\""

  # Robot add issue to "<project>" [traker <id>] with "<subject>"
  robot.respond /add (?:issue )?(?:\s*to\s*)?(?:"?([^" ]+)"? )(?:tracker\s)?(\d+)?(?:\s*with\s*)("?([^"]+)"?)/i, (msg) ->
    [project_id, tracker_id, subject] = msg.match[1..3]

    attributes =
      "project_id": "#{project_id}"
      "subject": "#{subject}"

    if tracker_id?
      attributes =
        "project_id": "#{project_id}"
        "subject": "#{subject}"
        "tracker_id": "#{tracker_id}"

    chili.Issue().add attributes, (err, data, status) ->
      unless data?
        if status == 404
          msg.reply "Couldn't update this issue, #{status} :("
      else
        msg.reply "Done! Added issue #{data.id} with \"#{subject}\""

  # Robot assign <issue> to <user> ["note to add with the assignment]
  robot.respond /assign (?:issue )?(?:#)?(\d+) to (\w+)(?: "?([^"]+)"?)?/i, (msg) ->
    [id, userName, note] = msg.match[1..3]

    chili.Users name:userName, (err, data) ->
      unless data.total_count > 0
        msg.reply "Couldn't find any users with the name \"#{userName}\""
        return false

      # try to resolve the user using login/firstname -- take the first result (hacky)
      user = resolveUsers(userName, data.users)[0]

      attributes =
        "assigned_to_id": user.id

      # allow an optional note with the re-assign
      attributes["notes"] = "#{msg.message.user.name}: #{note}" if note?

      # get our issue
      chili.Issue(id).update attributes, (err, data, status) ->
        unless data?
          if status == 404
            msg.reply "Issue ##{id} doesn't exist."
          else
            msg.reply "There was an error assigning this issue."
        else
          msg.reply "Assigned ##{id} to #{user.firstname}."
          msg.send '/play trombone' if parseInt(id) == 3631

  # Robot chili me <issue>
  robot.respond /(?:chili|show)(?: me)? (?:issue )?(?:#)?(\d+)/i, (msg) ->
    id = msg.match[1]

    params =
      "include": "journals"

    chili.Issue(id).show params, (err, data, status) ->
      unless status == 200
        msg.reply "Issue ##{id} doesn't exist."
        return false

      issue = data.issue

      _ = []
      _.push "\n[#{issue.project.name} - #{issue.priority.name}] #{issue.tracker.name} ##{issue.id} (#{issue.status.name})"
      _.push "Assigned: #{issue.assigned_to?.name ? 'Nobody'} (opened by #{issue.author.name})"
      if issue.status.name.toLowerCase() != 'new'
         _.push "Progress: #{issue.done_ratio}% (#{issue.spent_hours} hours)"
      _.push "Subject: #{issue.subject}"
      _.push "\n#{issue.description}"

      # journals
      _.push "\n" + Array(10).join('-') + '8<' + Array(50).join('-') + "\n"
      for journal in issue.journals
        do (journal) ->
          if journal.notes? and journal.notes != ""
            date = formatDate journal.created_on, 'mm/dd/yyyy (hh:ii ap)'
            _.push "#{journal.user.name} on #{date}:"
            _.push "    #{journal.notes}\n"

      msg.reply _.join "\n"

  # Listens to #NNNN and gives ticket info
  robot.hear /.*(#(\d+)).*/, (msg) ->
    id = msg.match[1].replace /#/, ""

    ignoredUsers = process.env.HUBOT_CHILIPROJECT_IGNORED_USERS or ""

    #Ignore cetain users, like ChiliProject plugins
    if msg.message.user.name in ignoredUsers.split(',')
      return

    if isNaN(id)
      return

    params = []

    chili.Issue(id).show params, (err, data, status) ->
      unless status == 200
        # Issue not found, don't say anything
        return false

      issue = data.issue

      url = "#{chili.url}/issues/#{id}"
      msg.send "#{issue.tracker.name} ##{issue.id} -- #{issue.project.name}::#{issue.subject} -- #{issue.status.name}::#{issue.priority.name} #{url}"


# simple ghetto fab date formatter this should definitely be replaced, but didn't want to
# introduce dependencies this early
#
# dateStamp - any string that can initialize a date
# fmt - format string that may use the following elements
#       mm - month
#       dd - day
#       yyyy - full year
#       hh - hours
#       ii - minutes
#       ss - seconds
#       ap - am / pm
#
# returns the formatted date
formatDate = (dateStamp, fmt = 'mm/dd/yyyy at hh:ii ap') ->
  d = new Date(dateStamp)

  # split up the date
  [m,d,y,h,i,s,ap] =
    [d.getMonth() + 1, d.getDate(), d.getFullYear(), d.getHours(), d.getMinutes(), d.getSeconds(), 'AM']

  # leadig 0s
  i = "0#{i}" if i < 10
  s = "0#{s}" if s < 10

  # adjust hours
  if h > 12
    h = h - 12
    ap = "PM"

  # ghetto fab!
  fmt
    .replace(/mm/, m)
    .replace(/dd/, d)
    .replace(/yyyy/, y)
    .replace(/hh/, h)
    .replace(/ii/, i)
    .replace(/ss/, s)
    .replace(/ap/, ap)

# tries to resolve ambiguous users by matching login or firstname
# ChiliProject's user search is pretty broad (using login/name/email/etc.) so
# we're trying to just pull it in a bit and get a single user
#
# name - this should be the name you're trying to match
# data - this is the array of users from ChiliProject
#
# returns an array with a single user, or the original array if nothing matched
resolveUsers = (name, data) ->
    name = name.toLowerCase();

    # try matching login
    found = data.filter (user) -> user.login.toLowerCase() == name
    return found if found.length == 1

    # try first name
    found = data.filter (user) -> user.firstname.toLowerCase() == name
    return found if found.length == 1

    # give up
    data

# ChiliProject API Mapping
# This isn't 100% complete, but its the basics for what we would need in campfire
class Chili
  constructor: (url, token) ->
    @url = url
    @token = token

  Users: (params, callback) ->
    @get "/users.json", params, callback

  User: (id) ->

    show: (callback) =>
      @get "/users/#{id}.json", {}, callback

  Projects: (params, callback) ->
    @get "/projects.json", params, callback

  Issues: (params, callback) ->
    @get "/issues.json", params, callback

  Issue: (id) ->

    show: (params, callback) =>
      @get "/issues/#{id}.json", params, callback

    update: (attributes, callback) =>
      @put "/issues/#{id}.json", {issue: attributes}, callback

    add: (attributes, callback) =>
      @post "/issues.json", {issue: attributes}, callback

  TimeEntry: (id = null) ->

    create: (attributes, callback) =>
      @post "/time_entries.json", {time_entry: attributes}, callback

  # Private: do a GET request against the API
  get: (path, params, callback) ->
    path = "#{path}?#{QUERY.stringify params}" if params?
    @request "GET", path, null, callback

  # Private: do a POST request against the API
  post: (path, body, callback) ->
    @request "POST", path, body, callback

  # Private: do a PUT request against the API
  put: (path, body, callback) ->
    @request "PUT", path, body, callback

  # Private: Perform a request against the ChiliProject REST API
  # from the campfire adapter :)
  request: (method, path, body, callback) ->
    headers =
      "Content-Type": "application/json"
      "X-ChiliProject-API-Key": @token

    endpoint = URL.parse(@url)
    pathname = endpoint.pathname.replace /^\/$/, ''

    options =
      "host"   : endpoint.hostname
      "port"   : endpoint.port
      "path"   : "#{pathname}#{path}"
      "method" : method
      "headers": headers

    if method in ["POST", "PUT"]
      if typeof(body) isnt "string"
        body = JSON.stringify body

      options.headers["Content-Length"] = body.length

    request = HTTP.request options, (response) ->
      data = ""

      response.on "data", (chunk) ->
        data += chunk

      response.on "end", ->
        switch response.statusCode
          when 200
            try
              callback null, JSON.parse(data), response.statusCode
            catch err
              callback null, (data or { }), response.statusCode
          when 401
            throw new Error "401: Authentication failed."
          else
            console.error "Code: #{response.statusCode}"
            callback null, null, response.statusCode

      response.on "error", (err) ->
        console.error "ChiliProject response error: #{err}"
        callback err, null, response.statusCode

    if method in ["POST", "PUT"]
      request.end(body, 'binary')
    else
      request.end()

    request.on "error", (err) ->
      console.error "ChiliProject request error: #{err}"
      callback err, null, 0
