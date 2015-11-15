debug = require('debug')('gulp-drive')
es = require('event-stream')
File = require('vinyl')
google = require('googleapis')
request = require('request')
gutil = require('gulp-util')
falloff = 100

makeFilename = (fileInfo)->
    extname = '.' + fileInfo.fileExtension
    filename = fileInfo.title

    # make sure filename includes extension
    filename.replace(new RegExp('('+extname+')?$','i'), extname)

    return filename

makeThumbnailFile = (file)->
    if file.info.thumbnailLink
        thumb = new File({
            path: file.path.replace(file.base, 't/')
            contents: new es.Stream.PassThrough
        })
        # debug("downloading thumbnail %s from %s", thumb.path, file.info.thumbnailLink)
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

    pool = {maxSockets: options.maxSockets ? 8}

    loadInfo = (metadata, callback)->
        drive.files.get({fileId: metadata.id}, (err, fileInfo)->
            if err
                if err.code is 403
                    debug("Rate limited. Trying again after %s ms", falloff)
                    if falloff > 300000
                        return callback(err)
                    setTimeout(->
                        loadInfo(metadata, callback)
                    , falloff)
                    falloff = falloff + 100
                    return
                else
                    return callback(err)
            debug("loaded info for %s", fileInfo.title)
            falloff = Math.max(falloff/1.1, 100)

            file = new File({
                path: makeFilename(fileInfo)
                contents: new es.Stream.PassThrough
            })
            file.info = fileInfo
            file.checksum = fileInfo.md5Checksum
            callback(null, file)
        )

    loadChildren = (folder)->
        @pause()
        drive.children.list({folderId: folder.info.id}, (err, children)=>
            if err then return @emit('error', err)
            debug("loaded folder %s with %s items", folder.path, children.items?.length)

            for item in children.items or []
                @emit('data', item)
            @resume()
        )

    loadRecursively = (item)->
        childDirs = []

        if item.info.mimeType is 'application/vnd.google-apps.folder'
            @pause()
            childStream = es.readArray([item])
            .pipe(es.through(loadChildren))
            .pipe(es.map(loadInfo))
            .pipe(es.through(loadRecursively))
            .pipe(es.mapSync((file)->
                # prepend parent's path to child's path
                file.path = item.path + '/' + file.path
                return file
            ))
            childStream.on('error', (err)->
                @emit('error', err)
            )
            childStream.on('data', (data)=>
                @emit('data', data)
            )
            childStream.on('end', =>
                @resume()
            )
        else
            @emit('data', item)

    plugin = {}
    plugin.src = (folderId)->
        basePath = ''

        es.readArray([{id: folderId}])
        .pipe(es.map(loadInfo))
        .pipe(es.mapSync((file)->
            # determine the name of the source folder
            basePath = file.path + '/'
            return file
        ))
        .pipe(es.through(loadRecursively))
        .pipe(es.mapSync((file)->
            # set every file.base to the source folder
            file.base = basePath
            return file
        ))

    plugin.fetch = es.through((file)->
        if file.info.webContentLink
            thumb = makeThumbnailFile(file)
            if thumb
                @emit('data', thumb)
                thumb.contents.on('error', (err)=>
                    @emit('error', err)
                )

            gutil.log("Downloading '#{gutil.colors.magenta(file.info.title)}' from #{gutil.colors.blue(file.info.webContentLink)}")
            req = request.get(file.info.webContentLink, {pool: pool})
            req.pipe(file.contents)
            req.on('error', (err)=>
                console.error("Error downloading '#{gutil.colors.magenta(file.info.title)}'", err)
                @emit('error', err)
            )

            @emit('data', file)
        else
            debug("skipping file %s", file.path)
            file.contents.end()
    )
  
    return plugin
