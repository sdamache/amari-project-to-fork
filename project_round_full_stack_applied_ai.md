# Final Round Project Assessment

## 🎉 Congratulations on making it this far. Welcome to the final round!

**Duration:** 3 hours

---

## Overview

In this project, you'll have to develop a **production-ready application** that takes in shipment documents and extracts data for the user.

### Allowed Tools

You're free to use any AI tools:

- OpenAI
- Claude
- Gemini
- Cursor
- GitHub Copilot
- etc.

> ⚠️ **No help from other humans is allowed.**

Use your best judgment on what to prioritize. You'll have to commit all your code at the end of the 3 hours.

You are given a starter code attached at the end of the document.

---

## Evaluation Criteria

You'll be judged on:

- What was completed
- Attention to detail
- Error handling
- Coding practices
- Robustness of the software

> 💡 Feel free to be creative, and let us know any assumptions made at the end.

---

## Project Components

### API

Create an API that takes in a list of document files and extracts relevant data.

- There can be multiple documents (PDFs and/or XLSX) related to a single shipment

### Documents

For testing, you'll be given two documents that belong to a shipment:

- A **bill of lading** (.pdf)
- A **commercial invoice and packing list** (.xlsx)

### LLM

You can use your own API key or ask the interviewer at the beginning of the interview.

### UI

Create a platform (React or any framework of your choice) with the following functionalities:

1. **Upload** the documents to extract data
2. **Show an editable form** with prefilled data
   - Fields to be extracted: [https://forms.gle/11kUya5nTebvFBgn7](https://forms.gle/11kUya5nTebvFBgn7)
3. **Option to view the documents** on the side with the extracted data for easy audit

---

## Bonus Work

### Deployment

Make the application production-ready by containerizing it with Docker.

- Include all dependencies
- Setup network between the containers

### Evaluation

Come up with an eval script that calculates:

- Accuracy
- Precision
- Recall
- F1 Score

> This will help us understand how robust the product is.

### Testing

Write unit tests for the functions.

- You can use the `pytest` library for unit tests

---

## Boilerplate

**Link:** [https://github.com/Amari-AI/amari-project-to-fork](https://github.com/Amari-AI/amari-project-to-fork)

### Instructions

1. **Fork** this boilerplate
2. At the end of 3 hours, create a **PR against the main branch** of your forked repo

> ⚠️ Be aware that there might be multiple issues in the current boilerplate.

The purpose is to provide you with a starter code. Reuse the existing code as much as possible and change the template to best fit your solution.

**Don't be afraid to employ creative solutions!**

---

## Summary Checklist

### Required

- [x] API for document extraction (PDF & XLSX support)
- [x] LLM integration for data extraction
- [x] UI with document upload
- [x] Editable form with prefilled extracted data
- [x] Document viewer for audit 
- [x] Persistence
### Bonus

- [x] Docker containerization
- [x] Evaluation script (accuracy, precision, recall, F1)
- [x] Unit tests with pytest

---

*Good luck! 🚀*
