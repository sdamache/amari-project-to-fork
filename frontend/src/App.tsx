import { useState } from 'react'
import axios from 'axios'
import { FileUpload } from './components/FileUpload'
import { DocViewer } from './components/DocViewer'
import { ExtractionForm } from './components/ExtractionForm'
import type { ShipmentData } from './components/ExtractionForm'
import { Loader2 } from 'lucide-react'

function App() {
  const [files, setFiles] = useState<File[]>([])
  const [activeFileIndex, setActiveFileIndex] = useState<number>(0)
  const [data, setData] = useState<ShipmentData | null>(null)
  const [isLoading, setIsLoading] = useState<boolean>(false)

  const handleFilesSelected = async (selectedFiles: File[]) => {
    // Validation: Ensure both PDF and Excel are present
    const hasPdf = selectedFiles.some(f => f.name.toLowerCase().endsWith('.pdf'));
    const hasExcel = selectedFiles.some(f => f.name.toLowerCase().endsWith('.xlsx') || f.name.toLowerCase().endsWith('.xls'));

    if (!hasPdf || !hasExcel) {
      alert("Please upload both a PDF (Bill of Lading) and an Excel file (Packing List/Invoice) to proceed.");
      return;
    }

    setFiles(selectedFiles)
    setIsLoading(true)
    
    // Reset data
    setData(null);

    const formData = new FormData()
    selectedFiles.forEach(file => {
      formData.append('files', file)
    })

    try {
      const response = await axios.post<ShipmentData>('http://localhost:8000/process-documents', formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      })
      setData(response.data)
    } catch (error) {
      console.error('Extraction failed:', error)
      alert('Failed to extract data. Please check the console for details.')
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="h-screen flex flex-col bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm px-6 py-4 flex justify-between items-center z-10">
        <h1 className="text-xl font-bold text-gray-800">Logistics Data Extractor</h1>
        {files.length > 0 && (
            <button 
                onClick={() => setFiles([])} 
                className="text-sm text-gray-500 hover:text-red-500"
                disabled={isLoading}
            >
                Reset / New Upload
            </button>
        )}
      </header>

      {/* Main Content */}
      <main className="flex-1 overflow-hidden relative">
        {files.length === 0 ? (
          <div className="h-full flex items-center justify-center p-6">
            <div className="max-w-xl w-full">
               <h2 className="text-center text-2xl mb-8 font-light text-gray-600">Upload BL & Packing List to Start</h2>
              <FileUpload onFilesSelected={handleFilesSelected} isLoading={isLoading} />
            </div>
          </div>
        ) : (
          <div className="h-full flex">
            {/* Left Panel: Document Viewer */}
            <div className="w-1/2 h-full bg-gray-100 border-r border-gray-200 overflow-hidden">
              <DocViewer 
                files={files} 
                activeFileIndex={activeFileIndex} 
                setActiveFileIndex={setActiveFileIndex} 
              />
            </div>

            {/* Right Panel: Extraction Form */}
            <div className="w-1/2 h-full bg-white relative overflow-hidden">
              {isLoading && (
                <div className="absolute inset-0 bg-white/80 z-20 flex flex-col items-center justify-center backdrop-blur-sm">
                  <div className="bg-white p-6 rounded-lg shadow-xl flex flex-col items-center">
                    <Loader2 className="w-12 h-12 animate-spin text-blue-500 mb-4" />
                    <p className="text-lg font-medium text-gray-800">Extracting Data with Claude 3.5...</p>
                    <p className="text-sm text-gray-500 mt-2">This may take 10-20 seconds.</p>
                  </div>
                </div>
              )}
              <ExtractionForm data={data} />
            </div>
          </div>
        )}
      </main>
    </div>
  )
}

export default App
