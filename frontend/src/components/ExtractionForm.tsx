import React, { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import axios from 'axios';
import { Save, Download, Check, AlertCircle, Loader2 } from 'lucide-react';

export interface ShipmentData {
  bill_of_lading_number: string | null;
  container_number: string | null;
  consignee_name: string | null;
  consignee_address: string | null;
  date_of_export: string | null;
  line_items_count: number | null;
  total_gross_weight: number | null;
  total_invoice_amount: number | null;
  average_gross_weight: number | null;
  average_price: number | null;
}

interface ExtractionFormProps {
  data: ShipmentData | null;
}

export const ExtractionForm: React.FC<ExtractionFormProps> = ({ data }) => {
  const { register, setValue, getValues } = useForm<ShipmentData>();
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'success' | 'error'>('idle');

  useEffect(() => {
    if (data) {
      Object.keys(data).forEach((key) => {
        const k = key as keyof ShipmentData;
        setValue(k, data[k]);
      });
    }
  }, [data, setValue]);

  const handleDownload = () => {
    const currentData = getValues();
    const jsonString = JSON.stringify(currentData, null, 2);
    const blob = new Blob([jsonString], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const link = document.createElement('a');
    link.href = url;
    link.download = `shipment_data_${currentData.bill_of_lading_number || 'export'}.json`;
    document.body.appendChild(link);
    link.click();
    
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  const handleSaveToBackend = async () => {
    const currentData = getValues();
    setSaveStatus('saving');
    try {
      await axios.post('/save-shipment', currentData);
      setSaveStatus('success');
      setTimeout(() => setSaveStatus('idle'), 3000); // Reset after 3 seconds
    } catch (error) {
      console.error('Error saving to backend:', error);
      setSaveStatus('error');
      setTimeout(() => setSaveStatus('idle'), 3000);
    }
  };

  return (
    <div className="p-6 h-full overflow-y-auto">
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-xl font-bold text-gray-800">Extracted Data</h2>
        <div className="flex gap-2">
            <button
            onClick={handleDownload}
            className="px-3 py-2 bg-gray-100 text-gray-700 rounded-md hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-300 transition-colors duration-200 flex items-center gap-2 text-sm font-medium"
            title="Download JSON locally"
            >
            <Download size={16} />
            Download
            </button>
            
            <button
            onClick={handleSaveToBackend}
            disabled={saveStatus === 'saving' || saveStatus === 'success'}
            className={`px-4 py-2 rounded-md text-white focus:outline-none focus:ring-2 focus:ring-offset-2 transition-all duration-200 flex items-center gap-2 text-sm font-medium
                ${saveStatus === 'success' ? 'bg-green-600 hover:bg-green-700 focus:ring-green-500' : 
                saveStatus === 'error' ? 'bg-red-600 hover:bg-red-700 focus:ring-red-500' :
                'bg-blue-600 hover:bg-blue-700 focus:ring-blue-500'}`}
            >
            {saveStatus === 'saving' ? (
                <>
                <Loader2 size={16} className="animate-spin" />
                Saving...
                </>
            ) : saveStatus === 'success' ? (
                <>
                <Check size={16} />
                Saved
                </>
            ) : saveStatus === 'error' ? (
                <>
                <AlertCircle size={16} />
                Retry Save
                </>
            ) : (
                <>
                <Save size={16} />
                Save Changes
                </>
            )}
            </button>
        </div>
      </div>
      <form className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">BOL Number</label>
          <input
            {...register('bill_of_lading_number')}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Container Number</label>
          <input
            {...register('container_number')}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
          />
        </div>

         <div>
          <label className="block text-sm font-medium text-gray-700">Consignee Name</label>
          <input
            {...register('consignee_name')}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Consignee Address</label>
          <textarea
            {...register('consignee_address')}
            rows={3}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
            <div>
            <label className="block text-sm font-medium text-gray-700">Date of Export</label>
            <input
                type="date"
                {...register('date_of_export')}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
            />
            </div>
            <div>
            <label className="block text-sm font-medium text-gray-700">Line Items Count</label>
            <input
                type="number"
                {...register('line_items_count')}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
            />
            </div>
        </div>

        <div className="grid grid-cols-2 gap-4">
            <div>
            <label className="block text-sm font-medium text-gray-700">Total Gross Weight</label>
            <input
                type="number"
                step="0.01"
                {...register('total_gross_weight')}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
            />
            </div>
            <div>
            <label className="block text-sm font-medium text-gray-700">Total Invoice Amount</label>
            <input
                type="number"
                step="0.01"
                {...register('total_invoice_amount')}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
            />
            </div>
        </div>

        <div className="grid grid-cols-2 gap-4">
            <div>
            <label className="block text-sm font-medium text-gray-700">Avg Gross Weight</label>
            <input
                type="number"
                step="0.01"
                {...register('average_gross_weight')}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
            />
            </div>
            <div>
            <label className="block text-sm font-medium text-gray-700">Avg Price</label>
            <input
                type="number"
                step="0.01"
                {...register('average_price')}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm border p-2"
            />
            </div>
        </div>
      </form>
    </div>
  );
};
