#import "../../Utils.h"
#import "NoteRequestLog.h"
#import "NotesThemeRuntime.h"

// GIF notes with a song (Instagram 453+, experimental)
//
// Instagram's note schema has separate gifNoteCreateInfo and musicNoteCreateInfo fields, but the
// composer only keeps one kind of content. So the last song picked in the note composer is saved
// here, and added to the request when the note is posted with a GIF and no music. It's kept when
// the song is removed (switching to a GIF may need that) until the note is posted or a new one starts.

static NSDictionary *sciSavedSong; // clusterId, assetId, startTime, duration (seconds)

static NSString *SCIStringForKeys(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        if (![object respondsToSelector:NSSelectorFromString(key)]) continue;

        @try {
            id value = [object valueForKey:key];
            if (value && value != [NSNull null]) return [NSString stringWithFormat:@"%@", value];
        }
        @catch (NSException *exception) {}
    }
    return nil;
}

// Short message over whatever is on screen, so each step of this feature is visible
static void SCIShowSongMessage(NSString *message, BOOL success) {
    if (![SCIUtils getBoolPref:@"notes_gif_with_music"]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        JGProgressHUD *hud = [[JGProgressHUD alloc] init];
        hud.textLabel.text = message;
        hud.indicatorView = success ? [[JGProgressHUDSuccessIndicatorView alloc] init] : [[JGProgressHUDErrorIndicatorView alloc] init];
        hud.userInteractionEnabled = NO;
        [hud showInView:topMostController().view];
        [hud dismissAfterDelay:2.0];
    });
}

static void SCISaveSong(id audio, double startTime, double duration) {
    NSString *clusterId = SCIStringForKeys(audio, @[@"audioClusterId", @"audioClusterID"]);
    if (!clusterId.length) {
        if (audio) NSLog(@"[SCInsta] Notes: picked audio has no cluster id: %@", audio);
        return;
    }

    // The same song reported again (for example after the editor) keeps its start time
    if ([sciSavedSong[@"clusterId"] isEqualToString:clusterId] && startTime <= 0 && duration <= 0) return;

    NSMutableDictionary *song = [NSMutableDictionary dictionary];
    song[@"clusterId"] = clusterId;
    song[@"assetId"] = SCIStringForKeys(audio, @[@"audioAssetId", @"audioAssetID"]);
    song[@"startTime"] = @(MAX(0, startTime));
    song[@"duration"] = @(duration > 0 ? duration : 30);
    sciSavedSong = song;

    NSLog(@"[SCInsta] Notes: saved song %@ for GIF notes", song);

    NSString *title = SCIStringForKeys(audio, @[@"title", @"songName", @"displayTitle", @"name"]);
    SCIShowSongMessage(title.length ? [NSString stringWithFormat:@"♪ %@\nsaved for a GIF note", title] : @"♪ Song saved for a GIF note", YES);
}

// The composer's selected song (IGDirectNotesMusicNoteViewModel: selectedMusic, startTime)
static void SCISaveSongFromViewModel(id viewModel) {
    if (!viewModel) return; // Switching to a GIF clears the selection; keep the saved song

    id track = nil, startTime = nil;
    @try {
        if ([viewModel respondsToSelector:NSSelectorFromString(@"selectedMusic")]) track = [viewModel valueForKey:@"selectedMusic"];
        if ([viewModel respondsToSelector:NSSelectorFromString(@"startTime")]) startTime = [viewModel valueForKey:@"startTime"];
    }
    @catch (NSException *exception) {}

    SCISaveSong(track ?: viewModel, [startTime doubleValue], 0);
}

// Seconds from the audio editor, converted to the milliseconds note music uses elsewhere
// (start_time_in_ms in responses). Values that already look like milliseconds are kept.
static NSNumber *SCIMilliseconds(NSNumber *seconds) {
    double value = seconds.doubleValue;
    return @(llround(value > 1000 ? value : value * 1000));
}

static void SCIAddSavedSongToRequest(id request) {
    if (![SCIUtils getBoolPref:@"notes_gif_with_music"] || !sciSavedSong) return;

    @try {
        id params = [request valueForKey:@"noteCreateParams"];
        id info = [params valueForKey:@"noteCreateInfo"];
        if (![info valueForKey:@"gifNoteCreateInfo"] || [info valueForKey:@"musicNoteCreateInfo"]) return;

        Class musicClass = NSClassFromString(@"IGXDTMusicNoteCreateInfo");
        SEL initializer = NSSelectorFromString(@"initWithAudioClusterId:");
        if (![musicClass instancesRespondToSelector:initializer]) {
            SCIShowSongMessage(@"This Instagram version can't add songs to GIF notes", NO);
            return;
        }

        id music = ((id (*)(id, SEL, id))objc_msgSend)([musicClass alloc], initializer, sciSavedSong[@"clusterId"]);
        if (sciSavedSong[@"assetId"]) [music setValue:sciSavedSong[@"assetId"] forKey:@"audioAssetId"];
        [music setValue:SCIMilliseconds(sciSavedSong[@"startTime"]) forKey:@"startTime"];
        [music setValue:SCIMilliseconds(sciSavedSong[@"duration"]) forKey:@"duration"];

        [info setValue:music forKey:@"musicNoteCreateInfo"];
        NSLog(@"[SCInsta] Notes: added saved song to GIF note");
        SCIShowSongMessage(@"♪ Song added to your GIF note", YES);

        // One song per note
        sciSavedSong = nil;
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Notes: couldn't add song to GIF note: %@", exception.reason);
        SCIShowSongMessage([NSString stringWithFormat:@"Couldn't add the song: %@", exception.reason], NO);
    }
}

// Song picked in the note composer (Instagram 453+)
// Demangled name: IGDirectNotesCreationComposerUISwift.IGDirectNotesMusicComposerController
%hook _TtC36IGDirectNotesCreationComposerUISwift36IGDirectNotesMusicComposerController
- (void)audioEditorViewControllerDelegateDidTapDone:(id)editor selectedAudio:(id)audio audioStartTime:(double)startTime audioDuration:(double)duration selectedLyricPhrase:(id)lyrics {
    SCISaveSong(audio, startTime, duration);
    %orig;
}

- (void)audioBrowserViewController:(id)browser didSelectAudioTrack:(id)track context:(id)context {
    SCISaveSong(track, 0, 0);
    %orig;
}

- (void)audioBrowserViewController:(id)browser didTapAudioTrack:(id)track context:(id)context {
    SCISaveSong(track, 0, 0);
    %orig;
}

- (void)setSelectedMusicViewModel:(id)viewModel {
    SCISaveSongFromViewModel(viewModel);
    %orig;
}

%end

// A new note starts without a saved song or SCInsta theme
// Demangled name: IGDirectNotesCreationComposerUI.IGDirectNotesComposerViewController
%hook _TtC31IGDirectNotesCreationComposerUI35IGDirectNotesComposerViewController
- (void)viewDidLoad {
    sciSavedSong = nil;
    [SCINotesThemeRuntime setAppliedTheme:nil];
    %orig;
}

// The composer is told about every song change, however it was picked
- (void)musicComposerDidUpdateSelectedMusicModel:(id)viewModel isFromSpotifyShareSheet:(BOOL)fromSpotify {
    SCISaveSongFromViewModel(viewModel);
    %orig;
}
%end

// Every note request passes through here (Instagram 453+): add the saved song and fix up the theme
%hook IGDirectCreateNoteMutationQueryBuilder
+ (id)builderWithRequest:(id)request {
    SCIAddSavedSongToRequest(request);
    [SCINotesThemeRuntime applyThemeToNoteRequest:request];
    [SCINoteRequestLog recordObject:request title:@"Note request (IGDirectCreateNoteMutationQueryBuilder)"];

    return %orig;
}
%end
