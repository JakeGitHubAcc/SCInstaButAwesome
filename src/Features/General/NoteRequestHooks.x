#import "../../Utils.h"
#import "NoteRequestLog.h"
#import "NotesThemeRuntime.h"

// A new note starts without an SCInsta theme
// Demangled name: IGDirectNotesCreationComposerUI.IGDirectNotesComposerViewController
%hook _TtC31IGDirectNotesCreationComposerUI35IGDirectNotesComposerViewController
- (void)viewDidLoad {
    [SCINotesThemeRuntime setAppliedTheme:nil];
    %orig;
}
%end

// Every note request passes through here (Instagram 453+): fix up the theme and log it
%hook IGDirectCreateNoteMutationQueryBuilder
+ (id)builderWithRequest:(id)request {
    [SCINotesThemeRuntime applyThemeToNoteRequest:request];
    [SCINoteRequestLog recordObject:request title:@"Note request (IGDirectCreateNoteMutationQueryBuilder)"];

    return %orig;
}
%end
