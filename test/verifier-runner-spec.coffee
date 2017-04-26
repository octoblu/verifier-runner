{describe,beforeEach,afterEach,it} = global
{expect}   = require 'chai'
sinon          = require 'sinon'
_              = require 'lodash'
enableDestroy  = require 'server-destroy'
shmock         = require '@octoblu/shmock'
moment         = require 'moment'
VerifierRunner = require '../'

describe 'VerifierRunner', ->
  beforeEach ->
    @logService = shmock()
    enableDestroy(@logService)
    @logServiceUrl = "http://localhost:#{@logService.address().port}"

    @statsService = shmock()
    enableDestroy(@statsService)
    @statsServiceUrl = "http://localhost:#{@statsService.address().port}"
    @_currentTime = Date.now()

    @sut = new VerifierRunner {
      logUrl: "#{@logServiceUrl}/verifications/some-name"
      statsUrl: "#{@statsServiceUrl}/stats/some-name"
      logExpiresSeconds: 60
      intervalSeconds: 1
      timeoutSeconds: 1
      @_currentTime
    }

  afterEach (done) ->
    @logService.destroy()
    @statsService.destroy()
    @sut.stop done

  describe '->do', ->
    describe 'when successful', ->
      beforeEach (done) ->
        @reportResult = @logService.post '/verifications/some-name'
          .send {
            success: true,
            expires: moment(@_currentTime).add(60, 'seconds').utc().format()
          }
          .reply 201

        @reportStats = @statsService.post '/stats/some-name'
          .send {
            elapsed: 1
          }
          .reply 201

        @verifierFn = sinon.stub().yields null, [
          {elapsed: 1}
        ]

        @sut.do @verifierFn, (@error) =>
          done()

      it 'should not have an error', ->
        expect(@error).to.not.exist

      it 'should call the verifierFn', ->
        expect(@verifierFn).to.have.been.called

      it 'should report the result', ->
        @reportResult.done()

      it 'should report the stats', ->
        @reportStats.done()

  describe '->doForever', ->
    describe 'when successful', ->
      beforeEach (done) ->
        @reportResult = @logService.post '/verifications/some-name'
          .send {
            success: true,
            expires: moment(@_currentTime).add(60, 'seconds').utc().format()
          }
          .reply 201

        @reportStats = @statsService.post '/stats/some-name'
          .send {
            elapsed: 1
          }
          .reply 201

        @verifierFn = sinon.spy()
        wrappedFn = (next) =>
          @verifierFn()
          @sut.stop()
          _.delay next, 10, null, [
            elapsed: 1
          ]
        @startTime = Date.now()
        @sut.doForever wrappedFn, (@error) =>
          done()

      it 'should not have an error', ->
        expect(@error).to.not.exist

      it 'should have took less than 1 second', ->
        timeDiff = Date.now() - @startTime
        expect(timeDiff < 1000).to.be.true

      it 'should call the verifierFn', ->
        expect(@verifierFn).to.have.been.called

      it 'should report the result', ->
        @reportResult.done()

      it 'should report the stats', ->
        @reportStats.done()

    describe 'when timeout', ->
      beforeEach (done) ->
        @reportResult = @logService.post '/verifications/some-name'
          .send {
            success: false,
            expires: moment(@_currentTime).add(60, 'seconds').utc().format()
            error:
              code: 504
              message: 'Verifier Timeout'
          }
          .reply 201

        @verifierFn = sinon.spy()
        wrappedFn = (next) =>
          @verifierFn()
          @sut.stop()
          _.delay next, 1100, null, [
            elapsed: 1
          ]
        @startTime = Date.now()
        @sut.doForever wrappedFn, (@error) =>
          done()

      it 'should not have an error', ->
        expect(@error).to.not.exist

      it 'should have took more than 1 second', ->
        timeDiff = Date.now() - @startTime
        expect(timeDiff > 1000).to.be.true

      it 'should call the verifierFn', ->
        expect(@verifierFn).to.have.been.called

      it 'should report the result', ->
        @reportResult.done()
