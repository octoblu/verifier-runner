_        = require 'lodash'
async    = require 'async'
moment   = require 'moment'
request  = require 'request'
debug    = require('debug')('verifier-runner')

class VerifierRunner
  constructor: (options)->
    { @logUrl, @statsUrl, @logExpiresSeconds } = options
    { @intervalSeconds, @timeoutSeconds } = options
    { @_currentTime } = options
    throw new Error('VerifierRunner: requires logExpiresSeconds') unless @logExpiresSeconds?
    throw new Error('VerifierRunner: requires intervalSeconds') unless @intervalSeconds?
    throw new Error('VerifierRunner: requires timeoutSeconds') unless @timeoutSeconds?
    debug { @intervalSeconds, @timeoutSeconds, @logExpiresSeconds }

  do: (verifierFn, callback) =>
    throw new Error 'VerifierRunner->do: first argument must be a verifierFn function' unless _.isFunction verifierFn
    throw new Error 'VerifierRunner->do: second argument must be a callback function' unless _.isFunction callback
    timeout  = (@timeoutSeconds * 1000)
    debug "->do with timeout of #{@timeoutSeconds}s"
    verifierFnWithTimeout = async.timeout(verifierFn, timeout)
    verifierFnWithTimeout (error, stats=[]) =>
      error = @_convertError error
      debug 'verifier done!', { error }
      @_postResults { error }, (logError) =>
        return callback error if error?
        return callback logError if logError?
        async.each stats, @_postStats, callback

  doForever: (verifierFn, callback) =>
    throw new Error 'VerifierRunner->doForever: first argument must be a verifierFn function' unless _.isFunction verifierFn
    throw new Error 'VerifierRunner->doForever: second argument must be a callback function' unless _.isFunction callback
    debug '->doForever'
    interval = (@intervalSeconds * 1000)
    doAndDelay = (next) =>
      @do verifierFn, (error) =>
        return callback null if @stopping
        debug 'do got an error', error if error?
        debug "going to wait for #{@intervalSeconds}s"
        _.delay next, interval
    async.doUntil doAndDelay, @_shouldStop, callback

  stop: (callback=->) =>
    @stopping = true
    callback null

  _convertError: (error) =>
    return unless error?
    if error?.code == 'ETIMEDOUT'
      error.message = 'Verifier Timeout'
      error.code = 504
      delete error.stack if process.env.NODE_ENV == 'test'
    return error

  _getExpires: =>
    return moment(@_currentTime).add(@logExpiresSeconds, 'seconds').utc().format()

  _postResults: ({ error }, callback) =>
    return callback null unless @logUrl?
    json = {
      success: !error?
      expires: @_getExpires()
    }
    if error?
      json.error = _.pick(error, 'code', 'message', 'stack')
      delete json.error.code unless _.isInteger json.error.code
    debug 'logging results to verifier service', { @logUrl, json }
    request.post @logUrl, { json }, (error, response) =>
      debug 'logged results', {error, statusCode: response?.statusCode} if error?
      return callback error if error?
      if response.statusCode > 399
        return callback new Error "Unexpected status code: #{response.statusCode}"
      callback null

  _postStats: (stats,callback) =>
    return callback null unless @statsUrl?
    debug 'logging stats', { @statsUrl, stats }
    request.post @statsUrl, {json:stats}, (error, response) =>
      debug 'logged stats', {error, statusCode: response?.statusCode} if error?
      return callback error if error?
      if response.statusCode > 399
        return callback new Error "Unexpected status code: #{response.statusCode}"
      callback null

  _shouldStop: =>
    return @stopping

module.exports = VerifierRunner
