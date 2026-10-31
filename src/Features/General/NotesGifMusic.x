#import "../../Utils.h"
#import "NoteRequestLog.h"

// GIF notes with a song (Instagram 453+, experimental)
//
// Instagram's note schema has separate gifNoteCreateInfo and musicNoteCreateInfo fields, but the
// composer only keeps one kind of content. So the last song picked in the note composer is saved
// here, and added to the request when the note is posted with a GIF and no music.

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

static void SCISaveSong(id audio, double startTime, double duration) {
    NSString *clusterId = SCIStringForKeys(audio, @[@"audioClusterId", @"audioClusterID"]);
    if (!clusterId.length) return;

    NSMutableDictionary *song = [NSMutableDictionary dictionary];
    song[@"clusterId"] = clusterId;
    song[@"assetId"] = SCIStringForKeys(audio, @[@"audioAssetId", @"audioAssetID"]);
    song[@"startTime"] = @(MAX(0, startTime));
    song[@"duration"] = @(duration > 0 ? duration : 30);
    sciSavedSong = song;

    NSLog(@"[SCInsta] Notes: saved song %@ for GIF notes", song);
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
        if (![musicClass instancesRespondToSelector:initializer]) return;

        id music = ((id (*)(id, SEL, id))objc_msgSend)([musicClass alloc], initializer, sciSavedSong[@"clusterId"]);
        if (sciSavedSong[@"assetId"]) [music setValue:sciSavedSong[@"assetId"] forKey:@"audioAssetId"];
        [music setValue:SCIMilliseconds(sciSavedSong[@"startTime"]) forKey:@"startTime"];
        [music setValue:SCIMilliseconds(sciSavedSong[@"duration"]) forKey:@"duration"];

        [info setValue:music forKey:@"musicNoteCreateInfo"];
        NSLog(@"[SCInsta] Notes: added saved song to GIF note");

        // One song per note
        sciSavedSong = nil;
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Notes: couldn't add song to GIF note: %@", exception.reason);
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

- (void)audioEditorViewControllerDelegateDidTapRemoveAudio:(id)editor {
    sciSavedSong = nil;
    %orig;
}
%end

// A new note starts without a saved song
// Demangled name: IGDirectNotesCreationComposerUI.IGDirectNotesComposerViewController
%hook _TtC31IGDirectNotesCreationComposerUI35IGDirectNotesComposerViewController
- (void)viewDidLoad {
    sciSavedSong = nil;
    %orig;
}
%end

// Every note request passes through here (Instagram 453+)
%hook IGDirectCreateNoteMutationQueryBuilder
+ (id)builderWithRequest:(id)request {
    SCIAddSavedSongToRequest(request);
    [SCINoteRequestLog recordObject:request title:@"Note request (IGDirectCreateNoteMutationQueryBuilder)"];

    return %orig;
}
%end
