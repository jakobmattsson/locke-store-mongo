async = require 'async'
mongojs = require 'mongojs'

rootAppName = 'locke'

oneArg = (f) -> (x) => f.call(this, x)

propagate = (callback, f) ->
  (err, rest...) ->
    return callback(err) if err
    f(rest...)

noUser = (app, email) -> new Error("There is no user with the email '#{email}' for the app '#{app}'")
noApp = (app) -> new Error("Could not find an app with the name '#{app}'")
noNullPassword = -> new Error('Password cannot be null')
noEmptyPassword = -> new Error('Password must be a non-empty string')

exports.factory = (params) ->

  db = mongojs.connect params.connstr, ['apps', 'users']

  createApp = (app, email, callback) ->
    db.apps.findOne { name: app }, propagate callback, (match) ->
      return callback(new Error("App name '#{app}' is already in use")) if match?
      db.apps.save { name: app, owner: email, users: 0 }, oneArg(callback)

  getUser = (app, email, callback) ->
    db.apps.findOne { name: app }, propagate callback, (match) ->
      return callback(noApp(app)) if !match? && app != rootAppName
      db.users.findOne { app: app, email: email }, propagate callback, (user) ->
        callback null, user?.data

  deleteToken = (app, email, type, token, callback) ->
    db.apps.findOne { name: app }, propagate callback, (match) ->
      return callback(noApp(app)) if !match? && app != rootAppName
      db.users.findOne { app: app, email: email }, propagate callback, (user) ->
        return callback(noUser(app, email)) if !user?

        obj = {}
        obj[type] = { token: token }
        db.users.update { app: app, email: email }, { $pull: obj }, oneArg(callback)

  comparePassword: (app, user, password, callback) ->
    db.apps.findOne { name: app }, propagate callback, (data) ->
      return callback(noApp(app)) if !data? && app != rootAppName
      getUser app, user, propagate callback, (data) ->
        return callback(noUser(app, user)) if !data?
        callback null, data.password == password

  compareToken: (app, email, type, name, callback) ->
    db.apps.findOne { name: app }, propagate callback, (match) ->
      return callback(noApp(app)) if !match? && app != rootAppName
      db.users.findOne { app: app, email: email }, propagate callback, (data) ->
        return callback(noUser(app, email)) if !data?
        list = data[type] || []
        anymatch = list.filter (item) -> item.token == name
        tt = anymatch[0]
        return callback(new Error('Incorrect token')) if !tt?
        callback(null, tt.data)

  addToken: (app, email, type, name, tokenData, callback) ->
    db.apps.findOne { name: app }, propagate callback, (matchApp) ->
      return callback(noApp(app)) if !matchApp? && app != rootAppName
      db.users.findOne { app: app, email: email }, propagate callback, (user) ->
        return callback(noUser(app, email)) if !user?

        obj = {}
        obj[type] = { token: name, data: tokenData }
        db.users.update { app: app, email: email }, { $push: obj }, oneArg(callback)

  removeToken: (app, user, type, name, callback) ->
    deleteToken app, user, type, name, oneArg(callback)

  removeAllTokens: (app, email, type, callback) ->
    db.apps.findOne { name: app }, propagate callback, (match) ->
      return callback(noApp(app)) if !match? && app != rootAppName
      db.users.findOne { app: app, email: email }, propagate callback, (user) ->
        return callback(noUser(app, email)) if !user?

        obj = {}
        obj[type] = 1
        db.users.update { app: app, email: email }, { $unset: obj }, oneArg(callback)

  setUserData: (app, email, data, callback) ->

    if data? && Object.keys(data).indexOf('password') != -1
      return callback(noNullPassword()) if !data.password?
      return callback(noEmptyPassword()) if data.password == '' || typeof data.password != 'string'

    db.apps.findOne { name: app }, propagate callback, (matchApp) ->
      return callback(noApp(app)) if !matchApp? && app != rootAppName
      db.users.findOne { app: app, email: email }, propagate callback, (user) ->
        return callback(noUser(app, email)) if !user?

        setdata = {}
        Object.keys(data).forEach (key) ->
          setdata['data.' + key] = data[key]
        db.users.update { app: app, email: email }, { $set: setdata }, oneArg(callback)

  getUser: (app, user, callback) ->
    getUser app, user, callback

  createUser: (app, email, data, callback) ->
    return callback(noNullPassword()) if !data?.password?
    return callback(noEmptyPassword()) if data.password == '' || typeof data.password != 'string'

    db.apps.findOne { name: app }, propagate callback, (matchApp) ->
      return callback(noApp(app)) if !matchApp? && app != rootAppName # always allow creating a user for the rootApp, even if doesn't exist (it will create it)
      db.users.findOne { app: app, email: email }, propagate callback, (user) ->
        return callback(new Error("User '#{email}' already exists for the app '#{app}'")) if user?
        async.parallel [
          (callback) -> db.apps.update { name: app }, { $inc: { users: 1 } }, callback
          (callback) -> db.users.save { app: app, email: email, data: data }, callback
        ], oneArg(callback)

  removeUser: (app, email, callback) ->
    db.apps.findOne { name: app }, propagate callback, (matchApp) ->
      return callback(noApp(app)) if !matchApp? && app != rootAppName
      db.users.findOne { app: app, email: email }, propagate callback, (user) ->
        return callback(noUser(app, email)) if !user?
        async.parallel [
          (callback) -> db.apps.update { app: app }, { $inc: { users: -1 } }, callback
          (callback) -> db.users.remove { app: app, email: email }, callback
        ], oneArg(callback)

  createApp: (email, app, callback) ->
    db.users.findOne { app: rootAppName, email: email }, propagate callback, (user) ->
      return callback(noUser(rootAppName, email)) if !user?
      createApp app, email, oneArg(callback)

  getApps: (email, callback) ->
    db.users.findOne { app: rootAppName, email: email }, propagate callback, (user) ->
      return callback(noUser(rootAppName, email)) if !user?
      db.apps.find { owner: email }, propagate callback, (data) ->
        res = {}
        data.forEach (app) ->
          res[app.name] = { userCount: app.users }
        callback null, res

  deleteApp: (app, callback) ->
    return callback(new Error("It is not possible to delete the app '#{rootAppName}'")) if app == rootAppName
    db.apps.findOne { name: app }, propagate callback, (matchApp) ->
      return callback(noApp(app)) if !matchApp?
      db.apps.remove { name: app }, oneArg(callback)

  clean: (callback) ->
    db.apps.remove ->
      db.users.remove ->
        createApp rootAppName, null, oneArg(callback)
