should = require 'should'
core = require 'locke-store-test'
storeFactory = require('./coverage').require('db')

noErr = (f) -> (err, rest...) ->
  should.not.exist err
  f(rest...)

store = storeFactory.factory({ connstr: 'mongodb://localhost/locke' })

it "should have a clean-method", (done) ->
  store.createUser 'locke', 'email@test.com', { password: 'psspww' }, noErr ->
    store.createApp 'email@test.com', 'my-app', noErr ->
      store.getApps 'email@test.com', noErr (data) ->
        Object.keys(data).length.should.eql 1
        store.clean noErr ->
          store.getApps 'email@test.com', (err, data) ->
            err.should.eql "There is no user with the email 'email@test.com' for the app 'locke'"
            done()

core.runTests(store, store.clean)