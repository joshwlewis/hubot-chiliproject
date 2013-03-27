# Hubot Chiliproject

Light mapping of the ChilProject REST API that allows hubot access to some basic ChiliProject tasks. Once you have a ChiliProject
user (preferably one with enough access to modify tickets), add the following to your heroku/etc. config:

    heroku config:add HUBOT_CHILIPROJECT_BASE_URL="http://chiliproject.your-server.com"
    heroku config:add HUBOT_CHILIPROJECT_TOKEN="your api token here"

If using over SSL, add the following to your heroku config:

    heroku config:add HUBOT_CHILIPROJECT_SSL=1

## Showing issue details

* Hubot show me [issue id]
* Hubot chili me [issue id]

## Showing my issue (or another user's)

* Hubot show my issues
* Hubot show [user]'s issues
** [user] will attempt to match on ChiliProject firstname or login

## Re-Assigning tickets

* Hubot assign [issue id] to [user]

## Leaving notes on tickets

* Hubot update [issue id] with "[comments]"

## Create tickets

* Hubot add issue to "[project]" [traker id] with "[subject]"
** [tracker id] is optional and represent the number matching literal value Bug/Feature/...

## Get a link to an issue

* Hubot link me [issue id]

## Set the percent done of an issue

* Hubot set [issue id] to 100% "[comments]"
* Hubot add [hours] hours to [issue id] "[comments]"

## More coming!