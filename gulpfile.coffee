gulp = require('gulp')
cached = require('gulp-cached')
remember = require('gulp-remember')
es = require('event-stream')

config = {
    clientId: process.env.OAUTH_CLIENT_ID
    clientSecret: process.env.OAUTH_CLIENT_SECRET
    refreshToken: process.env.OAUTH_REFRESH_TOKEN
}

gulpDrive = require('./index.coffee')(config)

gulp.task('default', ['test'])

gulp.task('test', ->
    gulpDrive.src(process.env.GOOGLE_DRIVE_FOLDER_ID)
    .pipe(cached('assets'))
    .pipe(gulpDrive.fetch)
    .pipe(gulp.dest('./public/'))
)

gulp.task('test-cache', ['test'], ->
    gulpDrive.src(process.env.GOOGLE_DRIVE_FOLDER_ID)
    .pipe(cached('assets'))
    .pipe(gulpDrive.fetch)
    .pipe(es.map((file, callback)->
        callback(new Error("Shouldn't emit any files"))
        process.exit(1)
    ))
)
