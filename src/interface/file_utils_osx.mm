#if defined(__WXOSX__)
	#include <AppKit/AppKit.h>
	#include <Foundation/Foundation.h>
	#undef HAVE_CONFIG_H
#endif

#include "wx/osx/private.h"
#include "wx/wx.h"
#include "wx/evtloop.h"
#include "LocalListView.h"
#include "dragdropmanager.h"

wxDropSource* gCurrentSource = NULL;

@interface wxPasteboard2: NSObject <NSDraggingSource, NSPasteboardWriting>
{
		BOOL dragFinished;
		int resultCode;
		wxDropSource* impl;
}
- (void)setImplementation: (wxDropSource *)dropSource;
- (BOOL)finished;
- (NSDragOperation)code;
@property (retain) NSPasteboard* pb;
@property (retain) NSString* destination;
@property (retain) NSArray<NSPasteboardItem *> * holder;

@end
@implementation wxPasteboard2

- (void)setImplementation: (wxDropSource *)dropSource
{
	impl = dropSource;
}

- (BOOL)finished
{
	return dragFinished;
}

- (NSDragOperation)code
{
	return resultCode;
}

- (void)setup
{
	self = [super init];
	dragFinished = NO;
	resultCode = NSDragOperationNone;
	impl = 0;
}

- (NSDragOperation)draggingSession:(nonnull NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
	return NSDragOperationCopy;
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {

	resultCode = operation;
	dragFinished = YES;

	NSURL *pasteLocationURL = nil;
	NSString *pasteLocation = [self stringForType:@"com.apple.pastelocation"];
	if (pasteLocation) {
		pasteLocationURL = [NSURL URLWithString:pasteLocation];
	}
}

// NSPasteboardWriting
- (nullable id)pasteboardPropertyListForType:(nonnull NSPasteboardType)type
{
	return nil;
}

- (nullable NSString *)stringForType:(NSPasteboardType)type {
	NSString *pasteLocation = [self.pb stringForType:@"com.apple.pastelocation"];
	if (pasteLocation) {
		NSArray *urlComponents = [pasteLocation  componentsSeparatedByString:@"file://"];
		if ( urlComponents.count > 1 ) {
			self.destination = urlComponents[1];
		}
	}
	return nil;
}

- (nonnull NSArray<NSPasteboardType> *)writableTypesForPasteboard:(nonnull NSPasteboard *)pasteboard
{
	return @[ (__bridge NSString *)kPasteboardTypeFileURLPromise ];
}

@end

wxDragResult NSDragOperationToWxDragResult2(NSDragOperation code)
{
	switch (code)
	{
		case NSDragOperationGeneric:
			return wxDragCopy;
		case NSDragOperationCopy:
			return wxDragCopy;
		case NSDragOperationMove:
			return wxDragMove;
		case NSDragOperationLink:
			return wxDragLink;
		case NSDragOperationNone:
			return wxDragNone;
		case NSDragOperationDelete: {
			wxString msg;
			msg.Printf(_(""));
			wxMessageBoxEx(msg, _("Deleting Items with Dragginh is not supported"), wxICON_EXCLAMATION);
			return wxDragNone;
		}
		default:
			wxFAIL_MSG("Unexpected result code");
	}
	return wxDragNone;
}

char const* GetDownloadDirImpl() {
	return "~/Downloads";
}

wxDragResult wxDropSource2::DoDragDrop(int WXUNUSED(flags))

{
	wxASSERT_MSG( m_data, wxT("Drop source: no data") );

	wxDragResult result = wxDragNone;
	if ((m_data == NULL) && !(m_data->GetFormatCount() == 0))
		return result;
	if (m_window == NULL)
		return result;

	NSView* view = m_window->GetPeer()->GetWXWidget();
	if (view)
	{
		wxPasteboard2 *delegate = [wxPasteboard2 new];
		[delegate setup];

		NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];

		delegate.pb = pboard;

		OSStatus err = noErr;
		PasteboardRef pboardRef;
		PasteboardCreate((CFStringRef)[pboard name], &pboardRef);

		err = PasteboardClear( pboardRef );
		if ( err != noErr )
		{
			CFRelease( pboardRef );
			return wxDragNone;
		}
		PasteboardSynchronize( pboardRef );

		m_data->AddToPasteboard( pboardRef, 1 );

		NSEvent* theEvent = (NSEvent*)wxTheApp->MacGetCurrentEvent();
		wxASSERT_MSG(theEvent, "DoDragDrop must be called in response to a mouse down or drag event.");

		NSPoint down = [theEvent locationInWindow];

		gCurrentSource = (wxDropSource*) this;

		// add a dummy square as dragged image for the moment,
		// TODO: proper drag image for data
		NSSize sz = NSMakeSize(16,16);
		NSRect fillRect = NSMakeRect(0, 0, 16, 16);
		NSImage* image = [[NSImage alloc] initWithSize: sz];

		[image lockFocus];

		[[[NSColor whiteColor] colorWithAlphaComponent:0.8] set];
		NSRectFill(fillRect);
		[[NSColor blackColor] set];
		NSFrameRectWithWidthUsingOperation(fillRect,1.0f,NSCompositeDestinationOver);

		[image unlockFocus];

		[delegate setImplementation: (wxDropSource*) this];

		NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:delegate];

		[dragItem setDraggingFrame:NSMakeRect(0.0, 0.0, 16.0, 16.0) contents:[NSImage imageWithSize:NSMakeSize(64.0, 64.0) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
			[[NSColor whiteColor] setFill];
			NSRectFill(dstRect);
			return YES;
		}]];
		//                                                      NSDraggingSource
		[view beginDraggingSessionWithItems:@[dragItem] event:theEvent source:delegate];

		wxEventLoopBase * const loop = wxEventLoop::GetActive();
		while ( ![delegate finished] )
			loop->Dispatch();
		[delegate release];
		[image release];

		if (delegate.code == NSDragOperationDelete) {
			wxString msg;
			msg.Printf(_(""));
			wxMessageBoxEx(msg, _("Moving Items into Trash is not supported"), wxICON_EXCLAMATION);
			return result;
		}
		result = NSDragOperationToWxDragResult2([delegate code]);

		wxWindow* mouseUpTarget = wxWindow::GetCapture();

		if ( mouseUpTarget == NULL )
		{
			NSString *dest = delegate.destination;
			if ( dest)
			{

				CState* pState = CContextManager::Get()->GetCurrentContext();

				NSData *wstringData = [dest dataUsingEncoding:NSUTF8StringEncoding];

				const wxString dirRaw = wxCFStringRef::AsString(dest);

				std::wstring const& path = std::wstring((wchar_t*)[wstringData bytes], [wstringData length]);

				const std::wstring & dirPath = dirRaw.ToStdWstring();

				CLocalPath dir = CLocalPath(dirPath);

				const CDragDropManager* pDragDropManager = CDragDropManager::Get();
				if (pDragDropManager) {
					if (CLocalDataObject *obj = pDragDropManager->localDataObj) {

						pState->HandleDroppedFiles(obj, dir, wxDragCopy);
						gCurrentSource = nil;
						return wxDragNone;
					} else if (CRemoteDataObject *obj = pDragDropManager->remoteDataObj) {

						bool res = pState->DownloadDroppedFiles(obj, dir, false);
						if (!res) {
							gCurrentSource = nil;
							return wxDragNone;
						}
					}
				} else {
					printf("pDragDropManager missing \n");
				}
			} else  {
				mouseUpTarget = m_window;
			}
		}

		if ( mouseUpTarget != NULL )
		{
			wxMouseEvent wxevent(wxEVT_LEFT_DOWN);
			((wxWidgetCocoaImpl*)mouseUpTarget->GetPeer())->SetupMouseEvent(wxevent , theEvent) ;
			wxevent.SetEventType(wxEVT_LEFT_UP);

			mouseUpTarget->HandleWindowEvent(wxevent);
		}

		gCurrentSource = NULL;
	}

	return result;
}

