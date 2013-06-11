delayTime = 30

id = 0
recieptHandle = 0

class SQSQueue
  constructor: (Attributes) ->
    @messages = []
    @hiddenMessages = {}
    @waitingRequests = []
    @delayedMessageCount = 0

    @VisibilityTimeout = 60
    @CreatedTimestamp = new Date().valueOf()
    @LastModifiedTimestamp = @CreatedTimestamp
    @DelaySeconds = 0
    @ReceiveMessageWaitTimeSeconds = 1

    @[key] = Attributes[key] for key in Object.keys(Attributes) if Attributes?

  getAttributes: ->
    {
      ApproximateNumberOfMessages: @messages.length,
      ApproximateNumberOfMessagesNotVisible: @hiddenMessages.length,
      VisibilityTimeout: @VisibilityTimeout,
      CreatedTimestamp: @CreatedTimestamp,
      LastModifiedTimestamp: @LastModifiedTimestamp
      ApproximateNumberOfMessagesDelayed: @delayedMessageCount,
      DelaySeconds: @DelaySeconds,
      ReceiveMessageWaitTimeSeconds: @ReceiveMessageWaitTimeSeconds
    }

  checkRequests: ->
    # Expected keys VisibilityTimeout, callback
    for request in @waitingRequests
      @getMessage request.VisibilityTimeout, 0, (err, data) =>
        if not err?
          i = @waitingRequests.indexOf request
          @waitingRequests.splice i, 1
          request.callback err, data

  addMessage: (body, delayTime) ->
    msg =
      Body: body
      MessageId: id++

    delayTime ?= @DelaySeconds
    if delayTime > 0
      @delayedMessageCount++
      setTimeout (=> 
        @delayedMessageCount--
        @messages.unshift(msg)
        @checkRequests()), delayTime * 1000
    else
      @messages.unshift(msg)
      process.nextTick =>
        @checkRequests()
    msg

  getMessage: (VisibilityTimeout, WaitTimeSeconds, callback) ->
    msg = @messages.pop()
    debugger
    WaitTimeSeconds ?= @ReceiveMessageWaitTimeSeconds

    if not msg?
      if WaitTimeSeconds is 0
        return callback new Error('No message available'), null
      else
        request = {VisibilityTimeout, callback}
        setTimeout (=>
          i = @waitingRequests.indexOf request

          return if i < 0

          item = @waitingRequests[i]
          @getMessage item.VisibilityTimeout, 0, item.callback
          @waitingRequests.splice i, 1), WaitTimeSeconds * 1000
        return @waitingRequests.unshift request

    msg.ReceiptHandle = recieptHandle++
    @hiddenMessages[msg.RecieptHandle] = msg
    setTimeout(VisibilityTimeout * 1000, (=> @returnMessage(msg.RecieptHandle)))
    callback null, msg

  returnMessage: (RecieptHandle) ->
    msg = @hiddenMessages[RecieptHandle]
    if msg?
      delete @hiddenMessages[RecieptHandle]
      @addMessage msg

  deleteMessage: (RecieptHandle) ->
    msg = @hiddenMessages[RecieptHandle]
    if msg?
      delete @hiddenMessages[RecieptHandle]
    else
      for i in [0..@messages.length]
        candidate = @messages[i]
        if candidate.RecieptHandle is RecieptHandle
          msg = candidate
          @messages.splice i, 1
          break

class SQS
  constructor: (options) ->
    @_messageQueues = {}
    @_nameToURL = {}

  createQueue: (options, callback) ->
    @getQueueUrl options, (err, data) =>
      if not err?
        callback null, data
      else
        url = options.QueueName
        @_nameToURL[options.QueueName] = url
        @_messageQueues[url] = new SQSQueue(options.Attributes)
        callback null, {QueueUrl:url}

  deleteMessage: (options, callback) ->
    QueueUrl = options.QueueUrl
    RecieptHandle = options.RecieptHandle
    queue = @_messageQueues[QueueUrl]
    message = queue.deleteMessage RecieptHandle
    
    if message?
      callback null, message
    else
      callback new Error("No message with that Reciept Handle"), null

  getQueueAttributes: (options, callback) ->
    QueueUrl = options.QueueUrl
    Attributes = options.Attributes
    attrs = @_messageQueues[QueueUrl].getAttributes()
    reqAttrs = {}
    for attrKey in Attributes
      attrVal = attrs[attrKey] 
      if attrVal?
        reqAttrs[attrKey] = attrVal
      else
        return callback new Error("KeyError: #{attrKey} is not a valid Attribute"), null
    callback null, {Attributes: reqAttrs}

  getQueueUrl: (options, callback) ->
    QueueName = options.QueueName
    url = @_nameToURL[QueueName]
    if not url?
      callback new Error("Queue with that name does not exist"), null
    else 
      callback null, {QueueUrl:url}

  recieveMessage: (options, callback) ->
    QueueUrl = options.QueueUrl
    MaxNumberOfMessages = options.MaxNumberOfMessages
    VisibilityTimeout = options.VisibilityTimeout
    WaitTimeSeconds = options.WaitTimeSeconds
    @_messageQueues[QueueUrl].getMessage VisibilityTimeout, WaitTimeSeconds, callback

  sendMessage: (options, callback) ->
    QueueUrl = options.QueueUrl
    MessageBody = options.MessageBody
    DelaySeconds = options.DelaySeconds
    msg = @_messageQueues[QueueUrl].addMessage MessageBody, DelaySeconds
    callback null, {MessageId: msg.MessageId}

module.exports = SQS