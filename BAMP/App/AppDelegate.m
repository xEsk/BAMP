//
//  AppDelegate.m
//  BAMP
//
//  Created by Xesc on 10/1/18.
//  Copyright © 2018 Beecubu. All rights reserved.
//

#import "AppDelegate.h"

#import "NSString+RegEx.h"
#import "STPrivilegedTask.h"

#define RowInternalPboardType @"RowInternalPboardType"

@interface AppDelegate () <NSTableViewDataSource, NSTextFieldDelegate>
{
    BOOL _mongoAlreadyRunning;
    
    NSString *_apacheConf;
    NSString *_currentDocumentsRoot;
	NSDictionary *_phpVersions;
    
    NSMutableArray<NSMutableDictionary *> *_documentRoots;
}

@property (weak) IBOutlet NSWindow *window;

@property (weak) IBOutlet NSVisualEffectView *uiBackground;
@property (weak) IBOutlet NSPopUpButton *uiPHPs;
@property (weak) IBOutlet NSSegmentedControl *uiServerStatus;
@property (weak) IBOutlet NSTableView *uiDocumentRoots;
@property (weak) IBOutlet NSButton *uiChangePHPCli;
@property (weak) IBOutlet NSTextField *uiCurrentPHPVersion;

@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // init configurations
    [self initApacheConfiguration];
    [self locateInstalledPHPs];
    _mongoAlreadyRunning = self.mongoIsRunning;
    _currentDocumentsRoot = self.currentDocumentRoot;
    // configure UI
    [self.uiServerStatus setSelected:YES forSegment:self.apacheIsRunning ? 0 : 1];
    [self.uiPHPs addItemsWithTitles:[_phpVersions.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
    [self.uiPHPs selectItemWithTitle:self.currentPHP];
    self.uiChangePHPCli.state = [[NSUserDefaults standardUserDefaults] boolForKey:@"cli"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.uiCurrentPHPVersion.stringValue = [NSString stringWithFormat:@"(%@)", self.currentPHPCliVersion];
	// load stored documents roots
	[self loadDocumentRoots];
	// configure drag and drop
	[self.uiDocumentRoots setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
	[self.uiDocumentRoots setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
	[self.uiDocumentRoots registerForDraggedTypes:@[RowInternalPboardType, NSFilenamesPboardType]];
	// show the potential php warnings
	[self parsePHPWarnings];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return YES;
}

#pragma mark - Tools

- (NSString *)userShell
{
   return [[NSProcessInfo processInfo] environment][@"SHELL"];
}

- (NSString *)runCommand:(NSString *)commandToRun
{
    NSTask *task = [NSTask new];
    task.launchPath = self.userShell;
    task.arguments = @[@"-l", @"-c", commandToRun];
    // create pipes
    NSPipe *inPipe = [NSPipe pipe];
    NSPipe *outPipe = [NSPipe pipe];
    // setup pipes
    [task setStandardInput:inPipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:outPipe];
    // run the command
    [task launch];
	// get the output
	NSString *output = [[NSString alloc] initWithData:[[outPipe fileHandleForReading] readDataToEndOfFile] encoding:NSUTF8StringEncoding];
#ifdef DEBUG
	NSLog(@"> %@", commandToRun);
	NSLog(@"-----------------");
	NSLog(@"%@", output);
	NSLog(@"=================");
#endif
    // capture output
	return output;
}

- (NSString *)sudoRunCommand:(NSString *)commandToRun
{
    STPrivilegedTask *task = [STPrivilegedTask new];
    task.launchPath = self.userShell;
    // configure the task to run
    task.arguments = @[@"-l", @"-c", commandToRun];
    // Launch it, user is prompted for password
    OSStatus err = [task launch];
    // parse auth result
    if (err == errAuthorizationSuccess)
    {
        // wait task to finish...
        [task waitUntilExit];
		// get the output
		NSString *output = [[NSString alloc] initWithData:[[task outputFileHandle] readDataToEndOfFile] encoding:NSUTF8StringEncoding];
#ifdef DEBUG
		NSLog(@"[SUDO] > %@", commandToRun);
		NSLog(@"-----------------");
		NSLog(@"%@", output);
		NSLog(@"=================");
#endif
        // capture output
		return output;
    }
    return nil;
}

- (void)openFile:(NSString *)path
{
	if ( ! [[NSWorkspace sharedWorkspace] openFile:path])
	{
		if ([[NSWorkspace sharedWorkspace] openFile:path withApplication:@"Sublime Text"]) return;
		if ([[NSWorkspace sharedWorkspace] openFile:path withApplication:@"TextEdit"]) return;
	}
}

#pragma mark - Apache methods

- (void)initApacheConfiguration
{
    if ( ! _apacheConf)
    {
        _apacheConf = [[self runCommand:@"apachectl -V | grep SERVER_CONFIG_FILE"] stringByMatching:@"SERVER_CONFIG_FILE=\"(.*?)\"" capture:1L];
        // exists?
        if ( ! [[NSFileManager defaultManager] fileExistsAtPath:_apacheConf])
        {
            NSLog(@"Error: Apache conf not found at %@", _apacheConf);
            // clean-up
            _apacheConf = nil;
        }
    }
}

- (BOOL)apacheIsRunning
{
    return [[self runCommand:@"ps -aef | grep httpd"] componentsSeparatedByString:@"\n"].count > 3;
}

- (BOOL)startApache
{
    if ([self sudoRunCommand:@"apachectl start"])
    {
        [self startMongoServer];
        // buuu
        return YES;
    }
    return NO;
}

- (BOOL)stopApache
{
    if ([self sudoRunCommand:@"apachectl stop"])
    {
        [self stopMongoServer];
        // buuu
        return YES;
    }
    return NO;
}

- (void)restartApache
{
    if (self.apacheIsRunning)
    {
        [self sudoRunCommand:@"apachectl -k restart"];
    }
}

- (IBAction)serverStatusToggle:(NSSegmentedControl *)sender
{
    if ((sender.selectedSegment == 0 && self.apacheIsRunning) || (sender.selectedSegment == 1 && ! self.apacheIsRunning)) return;
    
    if (sender.selectedSegment == 0)
    {
        if ( ! [self startApache])
        {
            sender.selectedSegment = 1;
        }
    }
    else // selectedSegment = 1
    {
        if ( ! [self stopApache])
        {
            sender.selectedSegment = 0;
        }
    }
}

- (IBAction)startApache:(id)sender
{
    if ([self startApache])
    {
        self.uiServerStatus.selectedSegment = 0;
    }
}

- (IBAction)stopApache:(id)sender
{
    if ([self stopApache])
    {
        self.uiServerStatus.selectedSegment = 1;
    }
}

- (IBAction)restartApache:(id)sender
{
    [self restartApache];
}

- (IBAction)openApacheConf:(id)sender
{
	[self openFile:_apacheConf];
}

#pragma mark - MongoDB server

- (BOOL)mongoIsRunning
{
    return [[self runCommand:@"ps -aef | grep mongod"] componentsSeparatedByString:@"\n"].count > 3;
}

- (void)startMongoServer
{
    if (_mongoAlreadyRunning) return;
    // start mongo server
    [self runCommand:@"ulimit -n 2048 && mongod --config /usr/local/etc/mongod.conf > /dev/null 2>&1 &"];
}

- (void)stopMongoServer
{
    if (_mongoAlreadyRunning) return;
    // stop mongo server
    [self runCommand:@"kill `pgrep mongod`"];
}

#pragma mark - PHP methods

- (void)locateInstalledPHPs
{
	NSMutableDictionary *phps = [NSMutableDictionary dictionary];
    // determine installed versions
    for (NSString *cellar in [[self runCommand:@"brew list"] componentsSeparatedByString:@"\n"])
    {
       if ([cellar isEqualToString:@"php"] || [cellar isMatchedByRegex:@"^php@\\d\\.\\d$"])
       {
		   for (NSString *fileName in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[@"/usr/local/Cellar/" stringByAppendingString:cellar] error:nil])
		   {
			   if ([fileName isMatchedByRegex:@"^\\d\\d?\\."])
			   {
				   [phps setObject:cellar forKey:fileName];
			   }
		   }
       }
    }
    // get the list
    _phpVersions = phps.copy;
}

- (NSString *)currentPHP
{
    NSString *conf = [[NSString alloc] initWithContentsOfFile:_apacheConf encoding:NSUTF8StringEncoding error:nil];
    // get the current php used in apache
    return [conf stringByMatching:@"^LoadModule\\s+php\\d_module\\s+.*\\/usr\\/local\\/Cellar\\/(.*?)\\/(.*?)\\/" capture:2L];
}

- (NSString *)currentPHPCliVersion
{
    return [[self runCommand:@"php -v"] stringByMatching:@"PHP ((\\d+)\\.(\\d+)\\.(\\d+))"];
}

- (NSString *)currentPHPCli
{
	return [self.currentPHPCliVersion stringByReplacingOccurrencesOfString:@"PHP " withString:@""];
}

- (NSString *)phpINIPath
{
	NSString *cellar = _phpVersions[self.currentPHP];
	NSString *path = [[self runCommand:[NSString stringWithFormat:@"brew --prefix %@", cellar]] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	return [[self runCommand:[NSString stringWithFormat:@"%@/bin/php -i", path]] stringByMatching:@"Loaded Configuration File => (.*)\n" capture:1L];
}

- (NSString *)resolveRealBrewPHPCliVersion
{
	NSString *path = [self runCommand:[NSString stringWithFormat:@"readlink %@", [self runCommand:@"which php"]]];
	return [path stringByMatching:@"\\/php(@\\d\\.\\d)?\\/(.+?)\\/" capture:2L];
}

- (void)changePHP
{
    // build the apache lib path
    NSString *php = self.uiPHPs.selectedItem.title;
    // update apache config if is needed
    if ( ! [self.currentPHP isEqualToString:php])
    {
		NSString *singleVersion = [php stringByMatching:@"(\\d\\d?)\\." capture:1L];
		NSString *path = [NSString stringWithFormat:@"/usr/local/Cellar/%@/%@/lib/httpd/modules/libphp%@.so", _phpVersions[php], php, singleVersion];
		// change php apache config
        NSString *conf = [[NSString alloc] initWithContentsOfFile:_apacheConf encoding:NSUTF8StringEncoding error:nil];
        NSString *phpModule = [conf stringByMatching:@"^LoadModule\\s+php\\d_module\\s+.*"];
        conf = [conf stringByReplacingOccurrencesOfString:phpModule withString:[NSString stringWithFormat:@"LoadModule php%@_module %@", singleVersion, path]];
        // save changes
        [conf writeToFile:_apacheConf atomically:YES encoding:NSUTF8StringEncoding error:nil];
        // restart apache
        [self restartApache];
		// capture possible warnings
		[self parsePHPWarnings];
    }
    // is the CLI checkbox on?
    if (self.uiChangePHPCli.state == NSControlStateValueOn)
    {
        NSString *currentPHPCli = self.currentPHPCli;
        // php really cahnged?
        if ( ! [currentPHPCli isEqualToString:php])
        {
			[self runCommand:[NSString stringWithFormat:@"brew unlink %@", _phpVersions[[self resolveRealBrewPHPCliVersion]]]];
			[self runCommand:[NSString stringWithFormat:@"brew switch %@ %@", _phpVersions[php], php]];
			[self runCommand:[NSString stringWithFormat:@"brew link --force %@", _phpVersions[php]]];
            // update current cli version
            self.uiCurrentPHPVersion.stringValue = [NSString stringWithFormat:@"(%@)", self.currentPHPCliVersion];
        }
    }
}

- (IBAction)phpChanged:(id)sender
{
    [self changePHP];
}

- (IBAction)phpCliOptionChanged:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:self.uiChangePHPCli.state == NSControlStateValueOn forKey:@"cli"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)openPhpINI:(id)sender
{
	[self openFile:self.phpINIPath];
}

- (void)parsePHPWarnings
{
	NSString *currentPHP = self.currentPHP;
	// capture the php cli outputs
	NSString *output = [self runCommand:[NSString stringWithFormat:@"/usr/local/Cellar/%@/%@/bin/php -v", _phpVersions[currentPHP], currentPHP]];
	// capture warnings
	NSArray *warnings = [output componentsMatchedByRegex:@"PHP Warning:(.*)(?:(?:\\r\\n|[\\r\\n])[^\\r\\n]+)*"];
	// there are some warnings?
	if (warnings.count > 0)
	{
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:[NSString stringWithFormat:@"PHP %@ (%ld warnings found)", [self currentPHP], warnings.count]];
		[alert setInformativeText:[warnings componentsJoinedByString:@"\n\n"]];
		[alert addButtonWithTitle:@"Continue"];
		[alert runModal];
	}
}

#pragma mark - Document root methods

- (void)saveDocumentRoots
{
    [[NSUserDefaults standardUserDefaults] setObject:_documentRoots forKey:@"documentRoots"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setApacheDocumentRoot:(NSString *)path
{
    NSString *conf = [[NSString alloc] initWithContentsOfFile:_apacheConf encoding:NSUTF8StringEncoding error:nil];
    // modify DocumentRoot directrive
    conf = [conf stringByReplacingOccurrencesOfRegex:[NSString stringWithFormat:@"DocumentRoot\\s*\"%@\"", _currentDocumentsRoot] withString:[NSString stringWithFormat:@"DocumentRoot \"%@\"", path]];
    // modify <Directory>
    conf = [conf stringByReplacingOccurrencesOfRegex:[NSString stringWithFormat:@"<Directory\\s*\"%@\"\\s*>", _currentDocumentsRoot] withString:[NSString stringWithFormat:@"<Directory \"%@\">", path]];
    // save changes
    [conf writeToFile:_apacheConf atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // update the current documents root
    _currentDocumentsRoot = path;
}

- (NSString *)currentDocumentRoot
{
    NSString *conf = [[NSString alloc] initWithContentsOfFile:_apacheConf encoding:NSUTF8StringEncoding error:nil];
    // get the current apache config
    return [conf stringByMatching:@"DocumentRoot\\s*\"(.*?)\"" capture:1L];
}

- (void)loadDocumentRoots
{
	_documentRoots = [NSMutableArray new];
	BOOL currentDocumentFound = NO;
	// convert each item to mutable dictionary
	for (NSDictionary *item in [[NSUserDefaults standardUserDefaults] arrayForKey:@"documentRoots"])
	{
		[_documentRoots addObject:[NSMutableDictionary dictionaryWithDictionary:item]];
		// is the current document root?
		if ([item[@"path"] isEqualToString:_currentDocumentsRoot]) currentDocumentFound = YES;
	}
	// not found?
	if ( ! currentDocumentFound)
	{
		NSMutableDictionary *item = [NSMutableDictionary dictionary];
		// config item
		item[@"alias"] = _currentDocumentsRoot.lastPathComponent;
		item[@"path"] = _currentDocumentsRoot;
		// add it
		[_documentRoots addObject:item];
	}
}

- (void)addDocumentRoot:(NSURL *)url index:(NSInteger)index
{
	NSMutableDictionary *item = [NSMutableDictionary dictionary];
	// config item
	item[@"alias"] = url.lastPathComponent;
	item[@"path"] = url.path;
	// add it
	[_documentRoots insertObject:item atIndex:index];
	// serialize changes
	[self saveDocumentRoots];
	// insert it animated
	[self.uiDocumentRoots beginUpdates];
	[self.uiDocumentRoots insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:index] withAnimation:NSTableViewAnimationSlideRight];
	[self.uiDocumentRoots endUpdates];
}

- (IBAction)addDocumentRootAction:(id)sender
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    // configure open panel
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    panel.allowsMultipleSelection = NO;
    // display open panel
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result)
    {
        if (result == NSModalResponseOK)
        {
			[self addDocumentRoot:panel.URLs.firstObject index:_documentRoots.count];
        }
    }];
}

- (IBAction)deleteDocumentRoot:(id)sender
{
    if (self.uiDocumentRoots.selectedRow != -1)
    {
        NSIndexSet *index = [NSIndexSet indexSetWithIndex:self.uiDocumentRoots.selectedRow];
        // remove it animated
        [self.uiDocumentRoots beginUpdates];
        [self.uiDocumentRoots removeRowsAtIndexes:index withAnimation:NSTableViewAnimationSlideLeft];
        [self.uiDocumentRoots endUpdates];
        // update data set
        [_documentRoots removeObjectsAtIndexes:index];
        // serialize changes
        [self saveDocumentRoots];
    }
}

- (IBAction)selectDocumentRoot:(id)sender
{
	if (self.uiDocumentRoots.clickedRow != -1)
	{
		NSString *selectedDocumentRool = _documentRoots[self.uiDocumentRoots.clickedRow][@"path"];
		// is not the current selection?
		if ( ! [_currentDocumentsRoot isEqualToString:selectedDocumentRool])
		{
			[self setApacheDocumentRoot:selectedDocumentRool];
			// reload table
			[self.uiDocumentRoots reloadData];
			// is the server active? then reload it
			[self restartApache];
		}
	}
}

- (IBAction)openFolder:(NSButton *)sender
{
	[[NSWorkspace sharedWorkspace] openFile:_documentRoots[[self.uiDocumentRoots rowForView:sender.superview]][@"path"]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _documentRoots.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    // is the alias cell?
    if ([tableColumn.identifier isEqualToString:@"alias"])
    {
        result.imageView.image = [_currentDocumentsRoot isEqualToString:_documentRoots[row][@"path"]] ? [NSImage imageNamed:@"NSStatusAvailableFlat"] : [NSImage imageNamed:@"NSStatusNoneFlat"];
    }
    // configure text
    result.textField.stringValue = _documentRoots[row][tableColumn.identifier];
    result.textField.delegate = self;
    // the view
    return result;
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
	[pboard declareTypes:@[RowInternalPboardType] owner:self];
	[pboard setData:data forType:RowInternalPboardType];
	// start dragging
	return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
	NSPasteboard* pboard = info.draggingPasteboard;
	// is a valid drop?
	if ([pboard.types containsObject:RowInternalPboardType] || [pboard.types containsObject:NSFilenamesPboardType])
	{
		return NSDragOperationEvery;
	}
	return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)destinationRow dropOperation:(NSTableViewDropOperation)dropOperation
{
	NSPasteboard* pboard = info.draggingPasteboard;
	// is an internal drag and drop?
	if ([pboard.types containsObject:RowInternalPboardType])
	{
		NSIndexSet *index = [NSKeyedUnarchiver unarchiveObjectWithData:[info.draggingPasteboard dataForType:RowInternalPboardType]];
		// prevent out of index
		if (destinationRow == _documentRoots.count) destinationRow -= 1;
		// move items
		NSMutableDictionary *original = _documentRoots[index.firstIndex];
		[_documentRoots removeObject:original];
		[_documentRoots insertObject:original atIndex:destinationRow];
		// serialize changes
		[self saveDocumentRoots];
		// reload table
		[self.uiDocumentRoots reloadData];
		// ok
		return YES;
	}
	// is a Finder drag and drop?
	else if ([pboard.types containsObject:NSFilenamesPboardType])
	{
		for (NSString *path in [pboard propertyListForType:NSFilenamesPboardType])
		{
			BOOL isDir;
			NSURL *url = [NSURL fileURLWithPath:path];
			// get information from this path
			[[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
			// is a file? then get his parent directory
			if ( ! isDir)
			{
				NSMutableArray *parts = url.pathComponents.mutableCopy;
				[parts removeLastObject];
				url = [NSURL URLWithString:[parts componentsJoinedByString:@"/"]];
			}
			// add element
			[self addDocumentRoot:url index:destinationRow];
		}
	}
	return NO;
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	[_documentRoots sortUsingDescriptors:[tableView sortDescriptors]];
	// serialize changes
	[self saveDocumentRoots];
	// update table
	[tableView reloadData];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSInteger row = [self.uiDocumentRoots rowForView:notification.object];
    NSString *cell = self.uiDocumentRoots.tableColumns[[self.uiDocumentRoots columnForView:notification.object]].identifier;
    // should restart??
    BOOL restart = [cell isEqualToString:@"path"] && [_currentDocumentsRoot isEqualToString:_documentRoots[row][@"path"]];
    // update the documents root
    _documentRoots[row][cell] = [notification.object stringValue];
    // serialize changes
    [self saveDocumentRoots];
    // should restart?
    if (restart && ! [_documentRoots[row][cell] isEqualToString:_currentDocumentsRoot])
    {
        [self setApacheDocumentRoot:_documentRoots[row][cell]];
        [self restartApache];
    }
}

@end

#pragma mark -

@interface CustomTextFieldCell: NSTableCellView @end

@implementation CustomTextFieldCell

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    self.textField.textColor = (backgroundStyle == NSBackgroundStyleDark) ? [NSColor whiteColor] : [NSColor textColor];
    // continue...
    [super setBackgroundStyle:backgroundStyle];
}

@end
