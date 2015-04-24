debug = require('debug')('gulp-drive')
es = require('event-stream')
File = require('vinyl')
google = require('googleapis')
request = require('request')

makeFilename = (fileInfo)->
    extname = '.' + fileInfo.fileExtension
    filename = fileInfo.title

    if (filename.indexOf(extname) isnt filename.length - extname.length)
        filename += extname

    return filename

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
            debug("fetching info for file %s", file.id)
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

    output.fetch = es.map((file, callback)->
        debug("downloading file %s from %s", file.path, file.info.webContentLink)
        request.get(file.info.webContentLink).pipe(file.contents)
        callback(null, file)
    )
    
    return output
