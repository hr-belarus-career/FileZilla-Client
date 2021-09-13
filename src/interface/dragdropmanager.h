#ifndef FILEZILLA_INTERFACE_DRAGDROPMANAGER_HEADER
#define FILEZILLA_INTERFACE_DRAGDROPMANAGER_HEADER

// wxWidgets doesn't provide any means to check on the type of objects
// while an object hasn't been dropped yet and is still being moved around
// At least on Windows, that appears to be a limitation of the native drag
// and drop system.

// As such, keep track on the objects.
#include "../include/serverpath.h"
#include "serverdata.h"
#include "dndobjects.h"

class CDragDropManager final
{
public:
	static CDragDropManager* Get() { return m_pDragDropManager; }

	static CDragDropManager* Init();
	void Release();

	const wxWindow* pDragSource;
	const wxWindow* pDropTarget;

	CLocalPath localParent;

	Site site;
	CServerPath remoteParent;

	CLocalDataObject *localDataObj;
	CRemoteDataObject *remoteDataObj;

protected:
	CDragDropManager();
	virtual ~CDragDropManager() = default;

	static CDragDropManager* m_pDragDropManager;
};

class wxDropSource2: public wxDropSource
{
	public :
		wxDropSource2( wxDataObject& data, wxWindow *win) {
			m_data = &data;
			m_window = win;
		};

		wxDragResult	DoDragDrop(int flags = wxDrag_CopyOnly) override;
		wxWindow*			GetWindow() { return m_window ; }

	protected :
		wxWindow        *m_window;
};
#endif
