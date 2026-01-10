import React, { useState, useEffect } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import { FileText, ChevronLeft, ChevronRight } from 'lucide-react';
import { read, utils } from 'xlsx';

// Set up worker
pdfjs.GlobalWorkerOptions.workerSrc = `//unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

interface DocViewerProps {
  files: File[];
  activeFileIndex: number;
  setActiveFileIndex: (index: number) => void;
}

export const DocViewer: React.FC<DocViewerProps> = ({ files, activeFileIndex, setActiveFileIndex }) => {
  const [numPages, setNumPages] = useState<number>(0);
  const [pageNumber, setPageNumber] = useState<number>(1);
  const [fileUrl, setFileUrl] = useState<string | null>(null);
  const [excelData, setExcelData] = useState<any[][] | null>(null);

  const activeFile = files[activeFileIndex];

  useEffect(() => {
    if (activeFile) {
      // Reset states
      setNumPages(0);
      setPageNumber(1);
      setFileUrl(null);
      setExcelData(null);

      const lowerName = activeFile.name.toLowerCase();

      if (lowerName.endsWith('.pdf')) {
        const url = URL.createObjectURL(activeFile);
        setFileUrl(url);
        return () => URL.revokeObjectURL(url);
      } else if (lowerName.endsWith('.xlsx') || lowerName.endsWith('.xls')) {
        const reader = new FileReader();
        reader.onload = (e) => {
          const data = new Uint8Array(e.target?.result as ArrayBuffer);
          const workbook = read(data, { type: 'array' });
          const sheetName = workbook.SheetNames[0];
          const worksheet = workbook.Sheets[sheetName];
          const json = utils.sheet_to_json(worksheet, { header: 1 });
          setExcelData(json as any[][]);
        };
        reader.readAsArrayBuffer(activeFile);
      }
    }
  }, [activeFile]);

  function onDocumentLoadSuccess({ numPages }: { numPages: number }) {
    setNumPages(numPages);
  }

  if (!activeFile) {
    return (
      <div className="h-full flex items-center justify-center bg-gray-100 text-gray-500">
        No document selected
      </div>
    );
  }

  const isPdf = activeFile.name.toLowerCase().endsWith('.pdf');
  const isExcel = activeFile.name.toLowerCase().endsWith('.xlsx') || activeFile.name.toLowerCase().endsWith('.xls');

  return (
    <div className="flex flex-col h-full border-r border-gray-200">
      {/* Tabs */}
      <div className="flex overflow-x-auto border-b border-gray-200 bg-white">
        {files.map((file, index) => (
          <button
            key={index}
            onClick={() => setActiveFileIndex(index)}
            className={`px-4 py-2 text-sm font-medium whitespace-nowrap
              ${index === activeFileIndex 
                ? 'text-blue-600 border-b-2 border-blue-600 bg-blue-50' 
                : 'text-gray-500 hover:text-gray-700 hover:bg-gray-50'
              }`}
          >
            {file.name}
          </button>
        ))}
      </div>

      {/* Viewer Content */}
      <div className="flex-1 overflow-auto bg-gray-100 p-4">
        {isPdf && fileUrl ? (
          <div className="flex flex-col items-center">
             <Document
                file={fileUrl}
                onLoadSuccess={onDocumentLoadSuccess}
                className="shadow-lg"
              >
                <Page 
                    pageNumber={pageNumber} 
                    renderTextLayer={false} 
                    renderAnnotationLayer={false}
                    width={500}
                />
              </Document>
              
              {numPages > 1 && (
                <div className="flex items-center gap-4 mt-4 bg-white px-4 py-2 rounded shadow">
                  <button 
                    disabled={pageNumber <= 1}
                    onClick={() => setPageNumber(p => p - 1)}
                    className="p-1 hover:bg-gray-100 rounded disabled:opacity-50"
                  >
                    <ChevronLeft size={20} />
                  </button>
                  <span className="text-sm">
                    Page {pageNumber} of {numPages}
                  </span>
                  <button 
                    disabled={pageNumber >= numPages}
                    onClick={() => setPageNumber(p => p + 1)}
                    className="p-1 hover:bg-gray-100 rounded disabled:opacity-50"
                  >
                    <ChevronRight size={20} />
                  </button>
                </div>
              )}
          </div>
        ) : isExcel && excelData ? (
          <div className="w-full h-full overflow-auto bg-white p-4 shadow-sm">
             <table className="min-w-full border-collapse border border-gray-300">
                <tbody>
                  {excelData.map((row, rowIndex) => (
                    <tr key={rowIndex} className="even:bg-gray-50">
                      {row.map((cell: any, cellIndex: number) => (
                        <td key={cellIndex} className="border border-gray-300 p-2 text-sm text-gray-700 whitespace-nowrap">
                          {cell}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
             </table>
          </div>
        ) : (
          <div className="h-full flex flex-col items-center justify-center text-gray-500">
            <FileText size={64} className="mb-4 text-gray-300" />
            <p className="text-lg font-medium">{activeFile.name}</p>
            <p className="mt-2 text-sm">Preview not available for this file type.</p>
          </div>
        )}
      </div>
    </div>
  );
};
