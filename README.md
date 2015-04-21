# Gulp-Google-Drive

Gulp module to load all files from a Google Drive folder.

### Usage

    config = {
        clientId: '...'
        clientSecret: '...'
        refreshToken: '...'
    }
    drive = require('gulp-google-drive', config)
    gulp.task('fetch-assets', (done)->
        drive.src('dir-id')
        .pipe(cached('assets'))
        .pipe(drive.fetch)
        .pipe(remember('assets'))
        .pipe(gulp.dest('public/'))
