debug = require('debug')('gulp-drive')
es = require('event-stream')
File = require('vinyl')
google = require('googleapis')
request = require('request')

makeFilename = (fileInfo)->
    extname = '.' + fileInfo.fileExtension
    filename = fileInfo.title

    # make sure filename includes extension
    filename.replace(new RegExp('('+extname+')?$','i'), extname)

    return filename

makeThumbnail = (file)->
    if file.info.thumbnailLink
        thumb = new File({
            path: 't/'+file.path
            contents: new es.Stream.PassThrough
        })
        debug("downloading thumbnail %s from %s", thumb.path, file.info.thumbnailLink)
        req = request.get(file.info.thumbnailLink)
        req.pipe(thumb.contents)
        req.on('error', (err)->
            thumb.contents.emit('error', err)
        )
        return thumb
    else
        return null

module.exports = (options)->
    clientId = options.clientId
    clientSecret = options.clientSecret
    unless clientId and clientSecret
        throw new Error("clientId and clientSecret must be set to the values at https://console.developers.google.com/project/${app_id}/apiui/credential")
    refreshToken = options.refreshToken
    unless refreshToken
        throw new Error("refreshToken must be set to a valid token")

    OAuth2 = google.auth.OAuth2
    client = new OAuth2(clientId, clientSecret, 'http://localhost/')
    client.setCredentials({refresh_token: refreshToken})
    drive = google.drive({version: 'v2', auth: client})

    output = {}
    output.src = (folderId, options)->
        # create an event-stream to be returned
        stream = new es.Stream()

        # load the folder and emit each fileInfo on it
        drive.children.list({folderId: folderId}, (err, folder)->
            debug("loaded #{folder.items.length} items")
            if err then return stream.emit('error', err)

            for item in folder.items or []
                stream.emit('data', item)

            stream.emit('end')
        )

        fileStream = stream.pipe(es.map((file, callback)->
            debug("loading info for file %s", file.id)
            drive.files.get({fileId: file.id}, (err, fileInfo)->
                if err then return callback(err)

                file = new File({
                    path: makeFilename(fileInfo)
                    contents: new es.Stream.PassThrough
                })
                # TODO: use info to make File correctly cacheable
                file.info = fileInfo
                callback(null, file)
            )
        ))

        return fileStream

    output.fetch = es.through((file)->
        if file.info.webContentLink
            thumb = makeThumbnail(file)
            if thumb
                @emit('data', thumb)
                thumb.contents.on('error', (err)=>
                    @emit('error', err)
                )

            debug("downloading file %s from %s", file.path, file.info.webContentLink)
            req = request.get(file.info.webContentLink)
            req.pipe(file.contents)
            req.on('error', (err)->
                @emit('error', err)
            )

            @emit('data', file)
        else
            debug("skipping file %s", file.info.title)
            file.contents.end()
    )
  
    return output
