import React, { useCallback } from 'react';
import { Upload } from 'lucide-react';

interface FileUploadProps {
  onFilesSelected: (files: File[]) => void;
  isLoading: boolean;
}

export const FileUpload: React.FC<FileUploadProps> = ({ onFilesSelected, isLoading }) => {
  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    if (isLoading) return;
    
    const droppedFiles = Array.from(e.dataTransfer.files);
    onFilesSelected(droppedFiles);
  }, [onFilesSelected, isLoading]);

  const handleChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && !isLoading) {
      const selectedFiles = Array.from(e.target.files);
      onFilesSelected(selectedFiles);
    }
  }, [onFilesSelected, isLoading]);

  return (
    <div 
      className={`border-2 border-dashed rounded-lg p-8 text-center transition-colors
        ${isLoading ? 'opacity-50 cursor-not-allowed' : 'hover:border-blue-500 cursor-pointer'}
        border-gray-300 bg-gray-50`}
      onDrop={handleDrop}
      onDragOver={(e) => e.preventDefault()}
    >
      <input
        type="file"
        multiple
        onChange={handleChange}
        className="hidden"
        id="file-upload"
        disabled={isLoading}
      />
      <label htmlFor="file-upload" className="cursor-pointer flex flex-col items-center">
        <Upload className="w-12 h-12 text-gray-400 mb-4" />
        <p className="text-lg font-medium text-gray-700">
          Drop PDF & Excel files here
        </p>
        <p className="text-sm text-gray-500 mt-2">
          or click to browse
        </p>
      </label>
    </div>
  );
};
